import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from scripts import release

ROOT = Path(__file__).resolve().parents[1]
COMMIT = 'a' * 40


class FakeGitHub(release.GitHub):
    """In-memory GitHub state; only upload/download temporary files are real."""
    def __init__(self, root):
        super().__init__(root, 'owner/repo')
        self.commands = []
        self.remote = None
        self.target = None
        self.contents = {}
        self.snapshot_calls = []
        self.failure = None

    def snapshot(self, commit, assets, metadata=False):
        self.snapshot_calls.append((commit, assets, metadata))

    def run(self, *args, missing=False):
        self.commands.append(args)
        if self.failure and self.failure in args:
            raise release.ReleaseError('Simulated API/upload failure')
        if args[:2] == ('gh', 'api'):
            endpoint = args[2]
            if endpoint.endswith('/git/refs'):
                self.target = next(x[4:] for x in args if x.startswith('sha='))
                return '{}'
            if '/git/ref/tags/' in endpoint:
                return json.dumps({'object': {'type': 'commit', 'sha': self.target}}) if self.target else None
            if '/releases/tags/' in endpoint:
                return json.dumps(self.remote) if self.remote and not self.remote['draft'] else None
            if endpoint.endswith('/releases'):
                return json.dumps(self.remote) if self.remote else ''
            return '{}'
        action = args[2]
        if action == 'create':
            self.remote = {'draft': True, 'assets': [], 'name': args[args.index('--title') + 1], 'body': ''}
        elif action == 'upload':
            for filename in args[4:args.index('--repo')]:
                path = Path(filename)
                if path.name in self.contents:
                    raise AssertionError('Attempted asset overwrite')
                self.contents[path.name] = path.read_bytes()
                self.remote['assets'].append({'name': path.name})
        elif action == 'download':
            name = args[args.index('--pattern') + 1]
            (Path(args[args.index('--dir') + 1]) / name).write_bytes(self.contents[name])
        elif action == 'edit':
            self.remote['body'] = Path(args[args.index('--notes-file') + 1]).read_text(encoding='utf-8')
            if '--draft=false' in args:
                self.remote['draft'] = False
        else:
            raise AssertionError(args)
        return ''


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='comfyui-release-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ('release.toml', 'Install_ComfyUI_venv_v7.bat', 'comfyui.bat', 'comfyui-start.bat'):
            shutil.copyfile(ROOT / name, self.root / name)
        self.meta = release.validate(self.root)
        self.gh = FakeGitHub(self.root)

    def existing(self, draft=False):
        self.gh.target = COMMIT
        self.gh.remote = {'draft': draft, 'name': self.meta['title'],
                          'body': self.meta['body'], 'assets': []}
        for value in self.meta['assets']:
            name = Path(value).name
            self.gh.remote['assets'].append({'name': name})
            self.gh.contents[name] = release.asset_bytes(self.root / value)

    def assert_no_mutations(self):
        for command in self.gh.commands:
            self.assertNotIn('--method', command)
            self.assertNotIn(command[2], ('create', 'upload', 'edit', 'delete'))

    def test_new_release_targets_exact_commit_and_verifies_before_publish(self):
        self.assertEqual(self.gh.publish(self.meta, COMMIT), 'published')
        self.assertEqual(self.gh.target, COMMIT)
        self.assertFalse(self.gh.remote['draft'])
        self.assertEqual(set(self.gh.contents), set(self.meta['assets']))
        self.assertEqual(self.gh.remote['body'], self.meta['body'])
        actions = [c[2] for c in self.gh.commands]
        self.assertLess(actions.index('download'), actions.index('edit'))

    def test_same_version_updates_only_body(self):
        self.existing()
        self.meta['body'] += '\nQuotes " and $() & shell metacharacters remain data.\n'
        self.assertEqual(self.gh.publish(self.meta, 'b' * 40), 'updated body')
        mutations = [c for c in self.gh.commands if c[2] in ('edit', 'upload', 'create')]
        self.assertEqual(len(mutations), 1)
        self.assertNotIn('--latest', mutations[0])
        self.assertNotIn('--title', mutations[0])
        self.assertEqual(self.gh.target, COMMIT)

    def test_unchanged_release_does_nothing(self):
        self.existing()
        self.assertEqual(self.gh.publish(self.meta, 'b' * 40), 'unchanged')
        self.assert_no_mutations()

    def test_changed_published_asset_is_rejected(self):
        self.existing()
        self.gh.contents['comfyui.bat'] += b'changed'
        with self.assertRaisesRegex(release.ReleaseError, 'increment the release version'):
            self.gh.publish(self.meta, COMMIT)
        self.assert_no_mutations()

    def test_changed_published_title_is_rejected(self):
        self.existing()
        self.meta['title'] = 'different title'
        with self.assertRaisesRegex(release.ReleaseError, 'increment the release version'):
            self.gh.publish(self.meta, COMMIT)
        self.assert_no_mutations()

    def test_existing_tag_never_moves(self):
        self.gh.target = 'b' * 40
        with self.assertRaisesRegex(release.ReleaseError, 'tags never move'):
            self.gh.publish(self.meta, COMMIT)
        self.assert_no_mutations()

    def test_partial_draft_resumes_only_missing_assets(self):
        self.existing(draft=True)
        del self.gh.contents['comfyui.bat']
        self.gh.remote['assets'] = [a for a in self.gh.remote['assets'] if a['name'] != 'comfyui.bat']
        self.assertEqual(self.gh.publish(self.meta, COMMIT), 'published')
        uploads = [c for c in self.gh.commands if c[2] == 'upload']
        self.assertEqual(len(uploads), 1)
        self.assertEqual(Path(uploads[0][4]).name, 'comfyui.bat')

    def test_draft_lookup_uses_paginated_list_after_by_tag_404(self):
        self.existing(draft=True)
        self.assertEqual(self.gh.get_release(self.meta['version']), self.gh.remote)
        self.assertTrue(any('--paginate' in c and c[2].endswith('/releases')
                            for c in self.gh.commands))

    def test_automation_fix_can_resume_identical_draft_without_moving_tag(self):
        self.existing(draft=True)
        self.assertEqual(self.gh.publish(self.meta, 'b' * 40), 'published')
        self.assertEqual(self.gh.target, COMMIT)
        self.assertIn((COMMIT, self.meta['assets'], True), self.gh.snapshot_calls)
        self.assertFalse(any('--method' in c or c[2] == 'upload' for c in self.gh.commands))

    def test_automation_fix_cannot_resume_changed_draft_snapshot(self):
        self.existing(draft=True)
        def reject_old(commit, assets, metadata=False):
            if commit == COMMIT:
                raise release.ReleaseError('Draft content differs from original tag')
        self.gh.snapshot = reject_old
        with self.assertRaises(release.ReleaseError):
            self.gh.publish(self.meta, 'b' * 40)
        self.assert_no_mutations()

    def test_conflicting_draft_is_not_modified(self):
        self.existing(draft=True)
        self.gh.contents['comfyui.bat'] = b'different'
        with self.assertRaises(release.ReleaseError):
            self.gh.publish(self.meta, COMMIT)
        self.assert_no_mutations()

    def test_upload_failure_leaves_draft(self):
        self.gh.failure = 'upload'
        with self.assertRaises(release.ReleaseError):
            self.gh.publish(self.meta, COMMIT)
        self.assertTrue(self.gh.remote['draft'])
        self.assertFalse(any(c[2] == 'edit' for c in self.gh.commands))

    def test_bad_asset_paths_and_duplicates_are_rejected(self):
        original = (self.root / 'release.toml').read_text(encoding='utf-8')
        cases = ['../outside.bat', '/absolute.bat', 'C:/outside.bat', 'missing.bat', 'comfyui.bat']
        for value in cases:
            with self.subTest(value=value):
                changed = original.replace('"comfyui-start.bat"]', json.dumps(value) + ']')
                (self.root / 'release.toml').write_text(changed, encoding='utf-8')
                with self.assertRaises(release.ReleaseError):
                    release.validate(self.root)

    def test_metadata_mismatches_are_rejected(self):
        original = (self.root / 'release.toml').read_text(encoding='utf-8')
        cases = [('v7.0install', 'latest'), ('v7.0install', 'v8.0install'),
                 ('2.12.1', '2.12.0'), ('3.13.13', '3.14.0')]
        for old, new in cases:
            with self.subTest(new=new):
                (self.root / 'release.toml').write_text(original.replace(old, new), encoding='utf-8')
                with self.assertRaises(release.ReleaseError):
                    release.validate(self.root)

    def test_malformed_toml_is_actionable(self):
        (self.root / 'release.toml').write_text('version = [', encoding='utf-8')
        with self.assertRaisesRegex(release.ReleaseError, 'Cannot read'):
            release.validate(self.root)

    def test_release_body_can_use_plain_prose_without_pip_commands(self):
        path = self.root / 'release.toml'
        text = path.read_text(encoding='utf-8')
        prose = 'Requires Python 3.13.13. Installs PyTorch 2.12.1 with cu130.\n'
        path.write_text(text.replace(self.meta['body'], prose), encoding='utf-8')
        self.assertEqual(release.validate(self.root)['body'], prose)

    def test_dry_run_and_validation_never_invoke_remote_commands(self):
        with patch.object(subprocess, 'run', side_effect=AssertionError('Unexpected command')):
            self.assertEqual(release.main(['validate', '--root', str(self.root)]), 0)
            self.assertEqual(release.main(['dry-run', '--root', str(self.root)]), 0)

    def test_auth_and_network_errors_are_not_missing_releases(self):
        gh = release.GitHub(self.root, 'owner/repo')
        for error in ('gh: Forbidden (HTTP 403)', 'connection timed out', 'gh: Bad credentials (HTTP 401)'):
            result = subprocess.CompletedProcess([], 1, '', error)
            with self.subTest(error=error), patch.object(subprocess, 'run', return_value=result):
                with self.assertRaises(release.ReleaseError):
                    gh.api('releases/tags/v7.0install', missing=True)
        result = subprocess.CompletedProcess([], 1, '', 'gh: Not Found (HTTP 404)')
        with patch.object(subprocess, 'run', return_value=result):
            self.assertIsNone(gh.api('releases/tags/v7.0install', missing=True))

    def test_publication_requires_exact_commit(self):
        self.assertEqual(release.main(['publish', '--root', str(self.root), '--commit', 'main']), 1)

    def test_snapshot_refuses_uncommitted_asset(self):
        gh = release.GitHub(self.root, 'owner/repo')
        result = subprocess.CompletedProcess([], 0, b'different committed content', b'')
        with patch.object(subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(release.ReleaseError, 'differs from target commit'):
                gh.snapshot(COMMIT, ['comfyui.bat'])

    def test_batch_asset_bytes_are_deterministic_crlf(self):
        self.assertEqual(release.canonical_bytes('x.bat', b'a\nb\r\n'), b'a\r\nb\r\n')
        self.assertEqual(release.canonical_bytes('x.md', b'a\nb\r\n'), b'a\nb\r\n')
