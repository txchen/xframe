#!/usr/bin/env python3
"""Verify tracked archives and restore local experimental models without downloads."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
ARCHIVES = ROOT / "experiments/mlx-dlss/weights"


def verify(data, record):
    if len(data) != record["bytes"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise ValueError(f"Checksum mismatch: {record['name']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/experiments/mlx-dlss/models/weights")
    args = parser.parse_args()
    manifest = json.loads((ARCHIVES / "manifest.json").read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    for model in manifest["models"]:
        chunks = []
        for part in model["parts"]:
            data = (ARCHIVES / part["name"]).read_bytes()
            verify(data, part)
            chunks.append(data)
        archive = b"".join(chunks)
        if hashlib.sha256(archive).hexdigest() != model["archive_sha256"]:
            raise ValueError(f"Archive checksum mismatch: {model['name']}")
        with tempfile.TemporaryDirectory(dir=args.output, prefix=".restore-") as staging:
            staging = Path(staging)
            with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
                expected = {m["name"] for m in model["members"]}
                if set(zipped.namelist()) != expected or len(zipped.namelist()) != len(expected):
                    raise ValueError("Unexpected archive members")
                for member in model["members"]:
                    relative = Path(member["name"])
                    if relative.is_absolute() or ".." in relative.parts:
                        raise ValueError("Unsafe archive path")
                    data = zipped.read(member["name"])
                    verify(data, member)
                    existing = args.output / relative
                    for parent in [existing, *existing.parents]:
                        if parent.is_symlink():
                            raise ValueError(f"Refusing symlink: {parent}")
                    if existing.exists():
                        verify(existing.read_bytes(), member)
                    elif (args.output / relative.parts[0]).exists():
                        raise ValueError(f"Incomplete existing model; choose a fresh output directory: {existing}")
                    target = staging / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
            for item in staging.iterdir():
                destination = args.output / item.name
                if destination.exists():
                    if destination.is_symlink():
                        raise ValueError(f"Refusing symlink: {destination}")
                    print(f"Verified existing: {destination}")
                else:
                    shutil.move(str(item), destination)
                    print(f"Restored: {destination}")


if __name__ == "__main__":
    main()
