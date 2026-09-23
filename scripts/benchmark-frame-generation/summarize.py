#!/usr/bin/env python3
"""Consolidate output from the two video runs and the DLSS stream run."""

import json
import hashlib
import platform
import sys
from pathlib import Path


def read(path: Path):
    return json.loads(path.read_text())


def main() -> None:
    work, video, pairs = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
    vt = read(work / "vt.json")
    vt_gpu = read(work / "vt-gpu.json")
    dlss = read(work / "dlss.json")
    dlss_gpu = read(work / "dlss-gpu.json")
    stream_gpu = read(work / "dlss-stream-gpu.json")
    stream = json.loads((work / "dlss-stream.stderr").read_text().splitlines()[-1])
    assert vt["pairs"] == pairs
    assert dlss["inputFrames"] == pairs + 1
    assert dlss["outputFrames"] == pairs * 2 + 1
    assert stream["generatedFrames"] == pairs
    digest = hashlib.sha256()
    with open(video, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)

    result = {
        "device": vt["device"],
        "macOS": platform.mac_ver()[0],
        "input": video,
        "inputSHA256": digest.hexdigest(),
        "size": [vt["width"], vt["height"]],
        "pairs": pairs,
        "targetIntervalMS": 1000 / 30,
        "videoToolbox": {
            "processP50MS": vt["steadyP50MS"],
            "processP95MS": vt["steadyP95MS"],
            "sessionStartMS": vt["sessionStartMS"],
            "attributedProcessGPUTimeMS": vt_gpu["gpuTimeObservedMS"],
            "gpuTimeAvailable": False,
            "gpuTimeNote": "VT's internal processing is not attributed to this process by AGX; a near-zero count does not establish near-zero device GPU work",
        },
        "dlssVideo": {
            "generationMeanWallMS": 1000 * dlss["timing"]["generationSeconds"] / pairs,
            "elapsedSeconds": dlss["elapsedSeconds"],
            "processGPUTimeObservedMS": dlss_gpu["gpuTimeObservedMS"],
            "processGPUTimePerGeneratedFrameMS": (dlss_gpu["gpuTimeObservedMS"] / pairs
                if dlss_gpu["gpuTimeObservedMS"] is not None else None),
            "gpuTimeNote": "whole process includes generation, decode, encode and setup; IORegistry final sample is a lower bound",
        },
        "dlssStream": {
            "meanWallMS": 1000 * stream["seconds"] / pairs,
            "processGPUTimeObservedMS": stream_gpu["gpuTimeObservedMS"],
            "processGPUTimePerGeneratedFrameMS": (stream_gpu["gpuTimeObservedMS"] / pairs
                if stream_gpu["gpuTimeObservedMS"] is not None else None),
            "gpuTimeNote": "raw RGB video frames, no decode or encode in measured process; includes input conversion and model startup",
        },
    }
    output = work / "summary.json"
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(output.read_text())


if __name__ == "__main__":
    main()
