# ComfyUI installation and startup scripts for Windows

`Install_ComfyUI_venv_v7.bat` builds on v6 and includes ComfyUI, a `.venv`,
ComfyUI-Manager as a custom node, and individually selectable acceleration packages.
Historical installers remain available; v7 does not need `install-sageattention_v4.bat`.

## Install

1. Install [Git for Windows](https://git-scm.com/downloads/win) and standard x64
   [CPython 3.13.13 or a later 3.13 patch](https://www.python.org/downloads/windows/).
   The supplied wheels do not target Python 3.14+, free-threaded Python, or ARM64.
2. Install a current [NVIDIA driver](https://www.nvidia.com/en-us/drivers/) for your GPU.
   R580 is the [CUDA 13.x baseline](https://docs.nvidia.com/deploy/cuda-compatibility/minor-version-compatibility.html);
   individual kernels and JIT compilation may require newer drivers/hardware.
3. Put the v7 installer in the parent folder where you want `ComfyUI` installed.
   Double-click it. Windows `curl.exe` and an internet connection are required.
4. Answer each optional package question. Enter means Yes; No preserves any
   existing installation of that package.
5. Run `ComfyUI\comfyui-start.bat` after installation.

Download both launcher assets beside the installer if desired. Otherwise v7
downloads missing launchers from its fixed release tag, not a moving `latest` URL.
Before v7 is published, run it from this repository with both launchers present.

## Package targets

```text
pip install torch==2.12.1 torchvision==0.27.1 --index-url https://download.pytorch.org/whl/cu130
```

cu130 is intentional; cu132 is excluded because of the maintainer-reported bug.
As in v6, the installer then installs the unchanged ComfyUI and Manager requirements
normally. TorchAudio is left to ComfyUI's requirements, not separately pinned to a
nonexistent 2.12.1 release. The resulting Torch/CUDA versions are checked.

| Optional package | Selected Windows build |
|---|---|
| Triton | `triton-windows<3.8` |
| SageAttention | 2.2.0, cu130, torch2.10.0andhigher, post6, cp310-abi3 |
| FlashAttention | 2.8.4, d20260328cu130torch2.12.0, cp313 |
| BlockSparseAttention | 0.0.2.post2, d20260117.cu130torch2.12.1, cp313 |
| SpargeAttn | 0.1.0, cu130, torch2.9.0andhigher, post4, cp39-abi3 |

Each package has its own default-yes prompt. If SageAttention or SpargeAttn needs
Triton after it was declined, dependency installation needs a separate answer.
Prebuilt-wheel installation does not itself require installing the CUDA Toolkit.
Installing packages does not activate attention backends automatically; the default
launcher does not pass `--enable-triton-backend`. GPU support varies by kernel.

## Reruns and troubleshooting

Existing environments and customized launchers are preserved. An incompatible
environment is not automatically rebuilt. Git updates are fast-forward-only and
stop on tracked local changes without automatic stashing, resetting, or merging.
Review the v7 launcher changes manually when upgrading an existing installation.

Exit code 0 means success; 1 means a prerequisite/core failure; 2 means the core
installed but requested extras or the final dependency check failed. Read the
per-package summary and the command error immediately above it. The installer
does not relax the Torch target or substitute wheels to hide an error.

Python overrides in the launchers should be executable paths without embedded
quotes, e.g. `set "PYTHON=C:\Python313\python.exe"`. `VENV_DIR` defaults to `.venv`
beside the launcher; `VENV_DIR=-` or `SKIP_VENV=1` skips activation.

## Maintaining releases

`release.toml` is the release source of truth: `version`, `title`, `installer`,
`assets`, and the Markdown `body`. Release versions use `v7.0install` or, for
example, `v7.0.1install`; the installer filename need not change for every patch.

- New assets or asset changes require a new version and a matching installer
  `RELEASE_TAG`. Update the body to describe the actual package targets.
- The same version permits body changes only. Published titles, assets and tags
  are never overwritten or moved. Release assets use deterministic CRLF for `.bat`.
- After review, committing and pushing `release.toml` to `main` triggers the release
  workflow. It validates, creates the tag at that exact commit, uploads a draft's
  assets, verifies their bytes, and publishes. A body-only change updates the old
  release without moving its tag to the newer commit.
- Manual dispatch on `main` retries publication. Matching partial drafts can resume;
  conflicting drafts/tags are left intact and reported. Do not manually move tags
  or replace assets to bypass a failure.

GitHub operations use `gh`. Actions uses `GITHUB_TOKEN` with `contents: write`
only in the publish job; no personal token or repository setting change is needed.
Forks target their own repository through `github.repository`.

```text
python -m unittest discover -s tests -v
python scripts/release.py validate
python scripts/release.py dry-run
```

Dry-run prints a local asset preview and hashes; it performs no remote checks or
mutations. Publication separately requires an exact committed SHA. The Windows
tests execute batch files with stub executables using the launcher bundled with
pip: they do not install GPU packages or start a real ComfyUI server. Import checks
and mocked tests are not GPU-workflow validation.
