# MLX-DLSS experimental model archives

These are the two locally extracted models requested for cross-machine experiments.
They are stored in ordinary Git, not Git LFS. NR's ZIP is split at 64 MiB so each
tracked file stays below GitHub's 100 MiB regular-file limit.

From the repository root, restore and verify both models with Python 3:

```sh
python3 scripts/restore-mlx-dlss-weights.py
```

Output: `.build/experiments/mlx-dlss/models/weights/`. The command checks SHA-256
for every part, reconstructed archive and extracted file. Matching existing
files are preserved; conflicting files cause an error. No model download or
third-party Python package is needed. A custom destination can be specified
with `--output PATH`.

| Model | ZIP bytes | Restored bytes |
| --- | ---: | ---: |
| FG `framegen.safetensors` | 2,684,627 | 2,891,168 |
| NR `NeuralRendering.dlssmodel` | 127,373,759 | 291,677,678 |

`manifest.json` records source URLs, hashes, fixed converter revision and archive
members. NR's source DLL differs from the converter's known DLL hash; all 153
packed tensors decoded successfully, but inference/vendor parity is unverified.
These NVIDIA-derived model data are separate from the upstream code license.
This check-in is for the user's experimental checkout and does not establish
redistribution rights for a public release.

See [experiment log](../../../.scratch/mlx-dlss-experiment/spec.md) for extraction
results and the remaining Metal toolchain prerequisite.
