# Repository instructions

## Installer maintenance

- Current installer: `Install_ComfyUI_venv_v7.bat`, based on v6's install flow.
- Target standard Windows x64 CPython 3.13.13+ within 3.13, torch 2.12.1,
  torchvision 0.27.1, and cu130. Do not silently upgrade or substitute this stack.
- Keep individual default-yes prompts for Triton, SageAttention, FlashAttention,
  BlockSparseAttention and SpargeAttn. Preserve the exact selected wheel URLs.
- Keep normal upstream requirements installation, including TorchAudio. Do not
  introduce a constraints file, filter requirements, or invent a matching audio release.
- Historical installers stay unchanged and are not new-release dependencies.
- Keep batch files readable, sectioned, quoted, and CRLF. Use small focused patches.
- Preserve unrelated workspace changes, existing environments and customized launchers.

## Release contract

- `release.toml` contains version, title, primary installer, explicit assets and body.
- A push changing that file on `main` triggers publication; tags are not the trigger.
- Match the installer's `RELEASE_TAG` to the metadata version.
- Changed assets or title require a new version. Same version changes body only.
- Never move existing tags or replace published assets. Matching partial drafts may resume.
- Use `gh` for GitHub operations. Do not commit/push/publish unless authorized.
- No scheduled dependency updates or automatic wheel substitutions.

## Required checks

- `python -m unittest discover -s tests -v` on Windows.
- `python scripts/release.py validate` and `python scripts/release.py dry-run`.
- `git diff --check` and scoped review of changed files.
- Tests use isolated command stubs; do not touch an active ComfyUI server or existing
  Python environment. Live GPU/startup tests require separate explicit authorization.
- Report observed failures and verification limits; do not speculate about incompatibility.
