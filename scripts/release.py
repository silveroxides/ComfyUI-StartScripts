"""Validate, preview, or publish release.toml. GitHub operations use gh only."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import subprocess
import tempfile
import tomllib


class ReleaseError(RuntimeError):
    pass


def asset_bytes(path: Path) -> bytes:
    """Release batch files with deterministic CRLF on every checkout platform."""
    data = path.read_bytes()
    return canonical_bytes(path.name, data)


def canonical_bytes(name: str, data: bytes) -> bytes:
    if name.lower().endswith('.bat'):
        return data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
    return data


def validate(root: Path) -> dict:
    root = root.resolve()
    try:
        meta = tomllib.loads((root / 'release.toml').read_text(encoding='utf-8'))
    except (OSError, ValueError) as exc:
        raise ReleaseError(f'Cannot read release.toml: {exc}') from exc
    if set(meta) != {'version', 'title', 'installer', 'assets', 'body'}:
        raise ReleaseError('release.toml requires exactly version, title, installer, assets, body')
    for key in ('version', 'title', 'installer', 'body'):
        if not isinstance(meta[key], str) or not meta[key].strip():
            raise ReleaseError(f'{key} must be a nonempty string')
    if not re.fullmatch(r'v[1-9][0-9]*\.[0-9]+(?:\.[0-9]+)?install', meta['version']):
        raise ReleaseError('Expected a version such as v7.0install or v7.0.1install')
    if '\n' in meta['title'] or '\r' in meta['title']:
        raise ReleaseError('Release title must be one line')
    assets = meta['assets']
    if not isinstance(assets, list) or not assets or not all(isinstance(x, str) for x in assets):
        raise ReleaseError('assets must be a nonempty list of paths')
    names = set()
    for value in assets:
        path = PurePosixPath(value)
        if (not value or '\\' in value or path.is_absolute() or
                PureWindowsPath(value).drive or '..' in path.parts or
                not re.fullmatch(r'[A-Za-z0-9_./-]+', value) or
                any(part.startswith('.') for part in path.parts)):
            raise ReleaseError(f'Unsafe asset path: {value}')
        resolved = (root / value).resolve()
        if not resolved.is_relative_to(root) or not resolved.is_file():
            raise ReleaseError(f'Missing asset or asset outside repository: {value}')
        if path.name.casefold() in names:
            raise ReleaseError(f'Duplicate asset filename: {path.name}')
        names.add(path.name.casefold())
    if meta['installer'] not in assets:
        raise ReleaseError('installer must be in assets')
    script = (root / meta['installer']).read_text(encoding='utf-8')
    declarations = dict(re.findall(r'^set "([A-Z_]+)=([^"\r\n]+)"\r?$', script, re.M))
    if declarations.get('RELEASE_TAG') != meta['version']:
        raise ReleaseError('Installer RELEASE_TAG must match release.toml version')
    for key in ('TORCH_VERSION', 'TORCHVISION_VERSION', 'CUDA_VARIANT', 'PYTHON_MIN'):
        if key not in declarations or declarations[key] not in meta['body']:
            raise ReleaseError(f'Release body must document installer {key}')
    command = (f"torch=={declarations['TORCH_VERSION']} "
               f"torchvision=={declarations['TORCHVISION_VERSION']} --index-url "
               f"https://download.pytorch.org/whl/{declarations['CUDA_VARIANT']}")
    if command not in script or command not in meta['body']:
        raise ReleaseError('Installer and release body must contain the declared Torch command')
    for name in ('comfyui.bat', 'comfyui-start.bat'):
        if name not in assets:
            raise ReleaseError(f'Missing launcher asset: {name}')
    return meta


class GitHub:
    def __init__(self, root: Path, repo: str):
        self.root = root
        self.repo = repo

    def run(self, *args: str, missing: bool = False) -> str | None:
        result = subprocess.run(args, cwd=self.root, capture_output=True, text=True,
                                encoding='utf-8')
        if result.returncode:
            if missing and '(HTTP 404)' in result.stderr:
                return None
            raise ReleaseError(f'{args[0]} {args[1]} failed: {result.stderr.strip()}')
        return result.stdout

    def api(self, suffix: str, missing: bool = False) -> dict | None:
        output = self.run('gh', 'api', f'repos/{self.repo}/{suffix}', missing=missing)
        return None if output is None else json.loads(output)

    def tag_commit(self, tag: str) -> str | None:
        ref = self.api(f'git/ref/tags/{tag}', missing=True)
        if ref is None:
            return None
        obj = ref['object']
        for _ in range(8):
            if obj['type'] == 'commit':
                return obj['sha']
            if obj['type'] != 'tag':
                break
            obj = self.api(f"git/tags/{obj['sha']}")['object']
        raise ReleaseError('Tag does not resolve to a commit')

    def snapshot(self, commit: str, assets: list[str], metadata: bool = False):
        """Refuse to release working-tree changes under an unrelated commit."""
        for name in assets + (['release.toml'] if metadata else []):
            result = subprocess.run(['git', 'show', f'{commit}:{name}'], cwd=self.root,
                                    capture_output=True)
            if result.returncode:
                raise ReleaseError(f'{name} is missing from target commit {commit}')
            expected = canonical_bytes(name, result.stdout)
            current = asset_bytes(self.root / name)
            if expected != current:
                raise ReleaseError(f'{name} differs from target commit; commit changes first')

    def verify_assets(self, release: dict, meta: dict, allow_missing: bool) -> list[str]:
        expected = {Path(x).name: x for x in meta['assets']}
        actual = [x['name'] for x in release['assets']]
        if len(set(actual)) != len(actual) or set(actual) - expected.keys():
            raise ReleaseError('Published asset set differs; increment the release version')
        missing = [path for name, path in expected.items() if name not in actual]
        if missing and not allow_missing:
            raise ReleaseError('Published assets are missing; increment the release version')
        with tempfile.TemporaryDirectory(prefix='comfyui-release-verify-') as directory:
            for name in actual:
                self.run('gh', 'release', 'download', meta['version'], '--repo', self.repo,
                         '--pattern', name, '--dir', directory)
                if (Path(directory) / name).read_bytes() != asset_bytes(self.root / expected[name]):
                    raise ReleaseError(f'Asset {name} differs; increment the release version')
        return missing

    def upload(self, tag: str, assets: list[str]):
        if not assets:
            return
        with tempfile.TemporaryDirectory(prefix='comfyui-release-upload-') as directory:
            staged = []
            for value in assets:
                path = Path(directory) / Path(value).name
                path.write_bytes(asset_bytes(self.root / value))
                staged.append(str(path))
            self.run('gh', 'release', 'upload', tag, *staged, '--repo', self.repo)

    def edit(self, meta: dict, publish: bool = False):
        with tempfile.TemporaryDirectory(prefix='comfyui-release-notes-') as directory:
            notes = Path(directory) / 'notes.md'
            notes.write_text(meta['body'], encoding='utf-8')
            args = ['gh', 'release', 'edit', meta['version'], '--repo', self.repo,
                    '--notes-file', str(notes)]
            if publish:
                args += ['--draft=false', '--latest']
            self.run(*args)

    def publish(self, meta: dict, commit: str) -> str:
        # Authenticate/check repository access before interpreting an endpoint's 404.
        self.run('gh', 'api', f'repos/{self.repo}')
        self.snapshot(commit, meta['assets'], metadata=True)
        tag = meta['version']
        release = self.api(f'releases/tags/{tag}', missing=True)
        target = self.tag_commit(tag)
        if release is not None and not release['draft']:
            if target is None:
                raise ReleaseError('Published release has no tag; refusing repair')
            if release['name'] != meta['title']:
                raise ReleaseError('Published title differs; increment the release version')
            try:
                self.snapshot(target, meta['assets'])
            except ReleaseError as exc:
                raise ReleaseError('Tagged assets differ; increment the release version') from exc
            self.verify_assets(release, meta, allow_missing=False)
            if (release.get('body') or '').replace('\r\n', '\n') == meta['body'].replace('\r\n', '\n'):
                return 'unchanged'
            self.edit(meta)
            return 'updated body'
        if target is not None and target != commit:
            raise ReleaseError('Existing tag targets a different commit; tags never move')
        if release is not None:
            if target is None or release['name'] != meta['title']:
                raise ReleaseError('Draft metadata/tag conflict; refusing automatic repair')
            missing = self.verify_assets(release, meta, allow_missing=True)
        else:
            missing = list(meta['assets'])
        if target is None:
            self.run('gh', 'api', f'repos/{self.repo}/git/refs', '--method', 'POST',
                     '-f', f'ref=refs/tags/{tag}', '-f', f'sha={commit}')
        if release is None:
            self.run('gh', 'release', 'create', tag, '--repo', self.repo, '--verify-tag',
                     '--target', commit, '--draft', '--title', meta['title'], '--notes', '')
        self.upload(tag, missing)
        uploaded = self.api(f'releases/tags/{tag}')
        self.verify_assets(uploaded, meta, allow_missing=False)
        self.edit(meta, publish=True)
        return 'published'


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('validate', 'dry-run', 'publish'))
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--repo', default='silveroxides/ComfyUI-StartScripts')
    parser.add_argument('--commit', help='Exact 40-character commit SHA; required for publication')
    args = parser.parse_args(argv)
    try:
        root = args.root.resolve()
        meta = validate(root)
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo):
            raise ReleaseError('Invalid repository name')
        result = 'validated'
        if args.mode == 'dry-run':
            print('Local preview only; no GitHub mutations or remote-state checks.')
            for name in meta['assets']:
                data = asset_bytes(root / name)
                print(f'{name}: {len(data)} bytes sha256:{hashlib.sha256(data).hexdigest()}')
            result = 'previewed'
        elif args.mode == 'publish':
            if not args.commit or not re.fullmatch(r'[0-9a-f]{40}', args.commit):
                raise ReleaseError('Publication requires --commit with an exact commit SHA')
            result = GitHub(root, args.repo).publish(meta, args.commit)
        url = f"https://github.com/{args.repo}/releases/tag/{meta['version']}"
        print(f"{meta['version']}: {result}\n{url}")
        if args.mode == 'publish' and os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
                summary.write(f"Release {result}: [{meta['version']}]({url})\n")
        return 0
    except (ReleaseError, OSError, ValueError, KeyError) as exc:
        print(f'ERROR: {exc}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
