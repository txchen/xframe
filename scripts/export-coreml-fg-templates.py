#!/usr/bin/env python3
"""Export weight-free Core ML FG graph templates and weight layout metadata.

Templates contain only the MIL graph structure (model.mlmodel + Manifest.json)
and zero third-party weight bytes. At runtime XFrame assembles weight.bin from
the user's verified framegen-310.7.0.safetensors file.
"""
import argparse
import hashlib
import json
import shutil
import struct
import tempfile
from pathlib import Path

import coremltools as ct
import numpy as np
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.mil import types
from safetensors.numpy import load_file

SHAPES = [
    ("368x640", 368, 640),   # 720p Quality (scale=2) & 1080p Balanced (scale=3)
    ("480x864", 480, 864),   # 1440p Balanced (scale=3)
    ("544x960", 544, 960),   # 1080p Quality (scale=2)
    ("720x1280", 720, 1280), # 1440p Quality (scale=2)
]


def export_graph(weights, stage, h, w):
    channels = (16, 18)[stage]
    spec = mb.TensorSpec(shape=(1, h, w, channels), dtype=types.fp16)

    @mb.program(input_specs=[spec], opset_version=ct.target.macOS15)
    def graph(x):
        def conv(x, layer, span=slice(None), activate=True, include_bias=True):
            prefix = f"block{stage}.{layer}"
            kwargs = {"x": x, "weight": weights[prefix + ".weight"][span], "pad_type": "same"}
            if include_bias:
                kwargs["bias"] = weights[prefix + ".bias"][span]
            y = mb.conv(**kwargs)
            if activate:
                y = mb.clip(
                    x=mb.leaky_relu(x=y, alpha=np.float16(0.01)),
                    alpha=np.float16(-6),
                    beta=np.float16(6),
                )
            return y

        def up(x):
            return mb.upsample_bilinear(
                x=x, scale_factor_height=2, scale_factor_width=2, align_corners=False
            )

        x = mb.transpose(x=x, perm=[0, 3, 1, 2])
        for i in range(3 - stage):
            x = mb.avg_pool(
                x=conv(x, f"stem{i}"),
                kernel_sizes=[2, 2],
                strides=[2, 2],
                pad_type="valid",
            )
        for i in range(0, 8, 2):
            x = mb.add(x=x, y=conv(conv(x, f"res{i}"), f"res{i+1}"))
        trunk = up(x)
        outs = [
            conv(up(conv(trunk, f"bot0.head{i}")), "bot1", span, False, include_bias=False)
            for i, span in enumerate((slice(0, 4), slice(4, 5), slice(5, 8)))
        ]
        return mb.transpose(x=mb.concat(values=outs, axis=1), perm=[0, 2, 3, 1])

    return ct.convert(
        graph,
        minimum_deployment_target=ct.target.macOS15,
        compute_units=ct.ComputeUnit.CPU_AND_NE,
    )


def ordered_weight_specs(stage, shapes_map):
    specs = []

    def add_conv(layer, span_start=None, span_end=None, include_bias=True):
        kinds = ("weight", "bias") if include_bias else ("weight",)
        for kind in kinds:
            name = f"block{stage}.{layer}.{kind}"
            shape = shapes_map[name]
            total_out = shape[0]
            s = 0 if span_start is None else span_start
            e = total_out if span_end is None else span_end
            row_elements = int(np.prod(shape[1:])) if len(shape) > 1 else 1
            byte_start = s * row_elements * 2
            byte_length = (e - s) * row_elements * 2
            specs.append(
                {
                    "tensor": name,
                    "byteOffset": byte_start,
                    "byteLength": byte_length,
                }
            )

    for i in range(3 - stage):
        add_conv(f"stem{i}")
    for i in range(0, 8, 2):
        add_conv(f"res{i}")
        add_conv(f"res{i+1}")
    for i, (s, e) in enumerate([(0, 4), (4, 5), (5, 8)]):
        add_conv(f"bot0.head{i}")
        add_conv("bot1", s, e, include_bias=False)
    return specs


def parse_weight_bin(path: Path):
    data = path.read_bytes()
    count, version = struct.unpack_from("<II", data, 0)
    assert version == 2, f"Unexpected blob version {version}"
    chunks = []
    offset = 64
    for _ in range(count):
        sentinel, dtype, size_bytes, data_offset = struct.unpack_from("<IIQQ", data, offset)
        assert sentinel == 0xDEADBEEF
        assert dtype == 1
        chunks.append((offset, data_offset, size_bytes, data[data_offset : data_offset + size_bytes]))
        offset = (data_offset + size_bytes + 63) & ~63
    return len(data), count, chunks


def build_weight_bin_from_layout(layout_stage, raw_weights):
    buf = bytearray(layout_stage["totalBytes"])
    struct.pack_into("<II", buf, 0, len(layout_stage["chunks"]), 2)
    for chunk in layout_stage["chunks"]:
        meta_off = chunk["metaOffset"]
        data_off = chunk["dataOffset"]
        size = chunk["byteLength"]
        struct.pack_into("<IIQQ", buf, meta_off, 0xDEADBEEF, 1, size, data_off)
        arr_bytes = np.ascontiguousarray(raw_weights[chunk["tensor"]], dtype=np.float16).tobytes()
        src = arr_bytes[chunk["tensorByteOffset"] : chunk["tensorByteOffset"] + size]
        assert len(src) == size
        buf[data_off : data_off + size] = src
    return bytes(buf)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("safetensors", type=Path, help="Verified framegen.safetensors for shape discovery & verification")
    parser.add_argument("output", type=Path, help="Destination directory for weight-free templates")
    args = parser.parse_args()

    real_weights = load_file(str(args.safetensors))
    shapes_map = {k: list(v.shape) for k, v in real_weights.items()}
    # Random non-degenerate dummy weights avoid MIL constant-dedup/zero-elimination passes while containing zero real weight data.
    rng = np.random.default_rng(12345)
    dummy_weights = {k: rng.standard_normal(v.shape).astype(np.float16) for k, v in real_weights.items()}

    if args.output.exists():
        shutil.rmtree(args.output)
    args.output.mkdir(parents=True)

    layout = {}
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for stage in (0, 1):
            # Reference export with real weights (temporary only, never saved to repo)
            ref_pkg = tmp / f"ref-block{stage}.mlpackage"
            export_graph(real_weights, stage, 368, 640).save(str(ref_pkg))
            ref_wbin = ref_pkg / "Data/com.apple.CoreML/weights/weight.bin"
            total_bytes, count, chunks = parse_weight_bin(ref_wbin)

            specs = ordered_weight_specs(stage, shapes_map)
            assert len(specs) == count, f"Expected {len(specs)} chunks, got {count}"

            # Match each chunk in weight.bin against our ordered specs by exact payload bytes
            matched_chunks = []
            used = set()
            for idx, (meta_off, data_off, size_bytes, payload) in enumerate(chunks):
                found = None
                for si, spec in enumerate(specs):
                    if si in used or spec["byteLength"] != size_bytes:
                        continue
                    arr_bytes = np.ascontiguousarray(real_weights[spec["tensor"]], dtype=np.float16).tobytes()
                    candidate = arr_bytes[spec["byteOffset"] : spec["byteOffset"] + size_bytes]
                    if candidate == payload:
                        found = (si, spec)
                        break
                assert found is not None, f"Stage {stage} chunk {idx} (size={size_bytes}) could not be matched"
                si, spec = found
                used.add(si)
                matched_chunks.append(
                    {
                        "metaOffset": meta_off,
                        "dataOffset": data_off,
                        "byteLength": size_bytes,
                        "tensor": spec["tensor"],
                        "tensorByteOffset": spec["byteOffset"],
                    }
                )

            layout[f"block{stage}"] = {
                "totalBytes": total_bytes,
                "chunks": matched_chunks,
            }
            rebuilt = build_weight_bin_from_layout(layout[f"block{stage}"], real_weights)
            assert rebuilt == ref_wbin.read_bytes(), f"Rebuilt weight.bin mismatch for stage {stage}!"
            print(f"Verified block{stage} weight.bin exact match: {hashlib.sha256(rebuilt).hexdigest()}")

            # Verify dummy-weight export produces the exact same model.mlmodel
            zero_pkg = tmp / f"zero-block{stage}.mlpackage"
            export_graph(dummy_weights, stage, 368, 640).save(str(zero_pkg))
            ref_ml = (ref_pkg / "Data/com.apple.CoreML/model.mlmodel").read_bytes()
            zero_ml = (zero_pkg / "Data/com.apple.CoreML/model.mlmodel").read_bytes()
            assert ref_ml == zero_ml, f"model.mlmodel differs between dummy and real weights for stage {stage}!"
            print(f"Verified block{stage} model.mlmodel is 100% weight-free ({len(zero_ml)} bytes)")

        # Export all required fixed-shape weight-free templates
        for label, h, w in SHAPES:
            for stage in (0, 1):
                pkg_tmp = tmp / f"block{stage}-{label}.mlpackage"
                export_graph(dummy_weights, stage, h, w).save(str(pkg_tmp))
                dest = args.output / f"block{stage}-{label}"
                dest.mkdir(parents=True)
                shutil.copy2(pkg_tmp / "Manifest.json", dest / "Manifest.json")
                shutil.copy2(pkg_tmp / "Data/com.apple.CoreML/model.mlmodel", dest / "model.mlmodel")
                print(f"Exported template: {dest.name} ({(dest / 'model.mlmodel').stat().st_size} bytes)")

    (args.output / "weight-layout.json").write_text(json.dumps(layout, indent=2) + "\n")
    print(f"Done. Templates written to {args.output}")


if __name__ == "__main__":
    main()
