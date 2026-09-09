"""Execute unmodified release batch files under cmd.exe with isolated command stubs."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == 'nt', 'Actual batch control flow requires Windows')
class WindowsBatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='comfyui-v7-tests-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'spaces (and) bang!'
        self.root.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.install = self.root / 'Install_ComfyUI_venv_v7.bat'
        for name in ('Install_ComfyUI_venv_v7.bat', 'comfyui.bat', 'comfyui-start.bat'):
            shutil.copyfile(ROOT / name, self.root / name)
        spec = importlib.util.find_spec('pip._vendor.distlib')
        self.assertIsNotNone(spec, 'Tests require the distlib launcher bundled with pip')
        launcher = (Path(spec.origin).parent / 't64.exe').read_bytes()
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, 'w') as zipped:
            zipped.writestr('__main__.py',
                            f'import sys\nsys.path.insert(0, {str(ROOT / "tests")!r})\n'
                            'import windows_stub\nraise SystemExit(windows_stub.main())\n')
        executable = launcher + f'#!"{sys.executable}"\n'.encode() + archive.getvalue()
        for name in ('where', 'git', 'curl', 'nvidia-smi', 'python', 'py'):
            (self.bin / (name + '.exe')).write_bytes(executable)
        self.settings = {}

    def run_batch(self, name=None, answers='n\nn\nn\nn\nn\n', extra_env=None, script_args=()):
        env = os.environ.copy()
        for name_to_clear in ('PYTHON', 'VENV_DIR', 'SKIP_VENV', 'COMMANDLINE_ARGS', 'GIT_PATH',
                              'PIP_INSTALLER_LOCATION'):
            env.pop(name_to_clear, None)
        env.update(STUB_ROOT=str(self.root), STUB_SOURCE=str(ROOT),
                   STUB_SETTINGS=json.dumps(self.settings), PATH=str(self.bin))
        env.update(extra_env or {})
        script = name or self.install
        input_file = self.root / 'answers.txt'
        input_file.write_bytes(answers.replace('\n', '\r\n').encode())
        with input_file.open('rb') as batch_input:
            result = subprocess.run([os.environ['COMSPEC'], '/d', '/c', 'call', str(script), *script_args],
                                    stdin=batch_input, capture_output=True,
                                    cwd=self.temp.name, env=env, timeout=30)
        self.output = (result.stdout + result.stderr).decode(errors='replace')
        log = self.root / 'calls.jsonl'
        self.calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return result.returncode

    def pip_installs(self):
        return [c['args'] for c in self.calls if c['args'][:3] == ['-m', 'pip', 'install']]

    def make_venv(self, directory=None):
        directory = directory or self.root / 'ComfyUI'
        scripts = directory / '.venv' / 'Scripts'
        scripts.mkdir(parents=True)
        shutil.copyfile(self.bin / 'python.exe', scripts / 'python.exe')
        (scripts / 'activate.bat').write_text('@echo off\nexit /b 0\n')
        return scripts

    def test_no_extras_preserves_v6_requirements_flow(self):
        self.assertEqual(self.run_batch(), 0, self.output)
        installs = self.pip_installs()
        self.assertEqual(len(installs), 3)
        self.assertEqual(installs[0][3:], ['torch==2.12.1', 'torchvision==0.27.1',
                                         '--index-url', 'https://download.pytorch.org/whl/cu130'])
        self.assertTrue(all('-c' not in call for call in installs))
        self.assertTrue(all('.venv' in c['exe'] for c in self.calls if c['args'][:2] == ['-m', 'pip']))
        self.assertTrue((self.root / 'ComfyUI' / 'comfyui-start.bat').exists())

    def test_default_yes_installs_all_exact_wheels(self):
        self.assertEqual(self.run_batch(answers='\n' * 5), 0, self.output)
        installs = self.pip_installs()
        self.assertEqual(len(installs), 8)
        self.assertEqual(installs[3][3:], ['-U', 'triton-windows<3.8'])
        urls = [args[3] for args in installs[4:]]
        expected = [
            'sageattention-2.2.0+cu130torch2.10.0andhigher.post6-cp310-abi3-win_amd64.whl',
            'flash_attn-2.8.4+d20260328cu130torch2.12.0cxx11abiTRUE-cp313-cp313-win_amd64.whl',
            'block_sparse_attn-0.0.2.post2+d20260117.cu130torch2.12.1cxx11abiTRUE-cp313-cp313-win_amd64.whl',
            'spas_sage_attn-0.1.0+cu130torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl',
        ]
        self.assertEqual([url.rsplit('/', 1)[1] for url in urls], expected)

    def test_invalid_answer_and_mixed_choices(self):
        self.assertEqual(self.run_batch(answers='invalid\nNo\nn\nYES\nno\nN\n'), 0, self.output)
        self.assertEqual(len(self.pip_installs()), 4)
        self.assertIn('flash_attn-', self.pip_installs()[-1][3])
        self.assertIn('Please enter Y or N', self.output)

    def test_declined_triton_requires_explicit_dependency_answer(self):
        self.assertEqual(self.run_batch(answers='n\ny\nn\nn\nn\nn\n'), 2, self.output)
        self.assertEqual(len(self.pip_installs()), 3)
        self.assertIn('SageAttention: blocked', self.output)

    def test_dependency_approval_installs_triton(self):
        self.assertEqual(self.run_batch(answers='n\ny\ny\nn\nn\nn\n'), 0, self.output)
        self.assertEqual(len(self.pip_installs()), 5)

    def test_optional_failure_continues_independent_packages(self):
        self.settings['fail'] = 'sageattention-2.2.0+'
        self.assertEqual(self.run_batch(answers='\n' * 5), 2, self.output)
        self.assertEqual(len(self.pip_installs()), 8)
        self.assertIn('SageAttention: failed', self.output)

    def test_torch_failure_is_fatal(self):
        self.settings['fail'] = 'torch==2.12.1'
        self.assertEqual(self.run_batch(), 1, self.output)
        self.assertEqual(len(self.pip_installs()), 1)

    def test_comfy_requirements_failure_is_fatal(self):
        self.settings['fail'] = 'ComfyUI\\requirements.txt'
        self.assertEqual(self.run_batch(), 1, self.output)
        self.assertEqual(len(self.pip_installs()), 2)

    def test_manager_failure_is_fatal(self):
        self.settings['fail'] = 'ComfyUI-Manager\\requirements.txt'
        self.assertEqual(self.run_batch(), 1, self.output)
        self.assertEqual(len(self.pip_installs()), 3)

    def test_rejects_unsupported_python_without_installing(self):
        cases = [dict(python_version=[3, 14, 0]), dict(python_version=[3, 13, 12]),
                 dict(python_version=[3, 12, 13]), dict(pointer_size=4),
                 dict(machine='ARM64'), dict(free_threaded=1), dict(missing_python=True)]
        for settings in cases:
            with self.subTest(settings=settings):
                self.settings = settings
                self.assertEqual(self.run_batch(), 1, self.output)
                self.assertEqual(self.pip_installs(), [])

    def test_missing_tools_fail_before_install(self):
        for tool in ('git.exe', 'curl.exe', 'nvidia-smi.exe'):
            with self.subTest(tool=tool):
                self.settings = {'missing': [tool]}
                self.assertEqual(self.run_batch(), 1, self.output)
                self.assertEqual(self.pip_installs(), [])

    def test_invalid_driver_output(self):
        for driver in ('', '579.99', 'unavailable', '581.80\n570.10'):
            with self.subTest(driver=driver):
                self.settings = {'driver': driver}
                self.assertEqual(self.run_batch(), 1, self.output)
                self.assertEqual(self.pip_installs(), [])

    def test_existing_incompatible_venv_is_preserved(self):
        scripts = self.make_venv()
        self.settings['python_version'] = [3, 12, 0]
        self.assertEqual(self.run_batch(), 1, self.output)
        self.assertTrue((scripts / 'python.exe').exists())
        self.assertFalse(any(c['args'][:2] == ['-m', 'venv'] for c in self.calls))

    def test_existing_checkout_uses_ff_only(self):
        self.make_venv()
        self.assertEqual(self.run_batch(), 0, self.output)
        pulls = [c['args'] for c in self.calls if 'pull' in c['args']]
        self.assertTrue(pulls)
        self.assertTrue(all('--ff-only' in args for args in pulls))

    def test_dirty_checkout_stops_without_stash(self):
        self.make_venv()
        self.settings['dirty'] = True
        self.assertEqual(self.run_batch(), 1, self.output)
        self.assertFalse(any('stash' in c['args'] or 'pull' in c['args'] for c in self.calls))

    def test_wrong_checkout_is_rejected(self):
        self.make_venv()
        self.settings['wrong_repo'] = True
        self.assertEqual(self.run_batch(), 1, self.output)

    def test_existing_launchers_are_not_overwritten(self):
        self.make_venv()
        for name in ('comfyui.bat', 'comfyui-start.bat'):
            (self.root / 'ComfyUI' / name).write_text('user customized launcher')
        self.assertEqual(self.run_batch(), 0, self.output)
        self.assertEqual((self.root / 'ComfyUI' / 'comfyui.bat').read_text(), 'user customized launcher')

    def test_download_missing_launchers_from_exact_tag(self):
        (self.root / 'comfyui.bat').unlink()
        (self.root / 'comfyui-start.bat').unlink()
        self.assertEqual(self.run_batch(), 0, self.output)
        downloads = [c['args'] for c in self.calls if Path(c['exe']).stem == 'curl']
        self.assertEqual(len(downloads), 2)
        self.assertTrue(all('/v7.0install/' in args[-1] and '--fail' in args for args in downloads))

    def test_invalid_download_is_not_installed(self):
        (self.root / 'comfyui.bat').unlink()
        self.settings['bad_download'] = True
        self.assertEqual(self.run_batch(), 1, self.output)
        self.assertFalse((self.root / 'ComfyUI' / 'comfyui.bat').exists())

    def test_launcher_default_venv_and_no_triton_flag(self):
        self.make_venv(self.root)
        self.assertEqual(self.run_batch(self.root / 'comfyui-start.bat', answers='n\n'), 0, self.output)
        launched = [c for c in self.calls if c['args'][:1] == ['main.py']]
        self.assertEqual(len(launched), 1)
        self.assertEqual(launched[0]['args'], ['main.py', '--windows-standalone'])
        self.assertIn('.venv', launched[0]['exe'])

    def test_launcher_honors_environment_override(self):
        scripts = self.make_venv(self.root / 'custom env')
        self.assertEqual(self.run_batch(self.root / 'comfyui.bat', answers='n\n',
                                       extra_env={'VENV_DIR': str(scripts.parent)}), 0, self.output)
        launched = [c for c in self.calls if c['args'][:1] == ['main.py']]
        self.assertEqual(Path(launched[0]['exe']), scripts / 'python.exe')

    def test_launcher_skip_venv_and_exit_code(self):
        self.settings['launch_exit'] = 7
        self.assertEqual(self.run_batch(self.root / 'comfyui.bat', answers='n\n',
                                       extra_env={'SKIP_VENV': '1', 'PYTHON': str(self.bin / 'python.exe')}),
                         7, self.output)

    def test_launcher_restart(self):
        self.make_venv(self.root)
        self.settings['restart'] = True
        self.assertEqual(self.run_batch(self.root / 'comfyui.bat', answers='n\n'), 0, self.output)
        self.assertEqual((self.root / 'launch_count').read_text(), '2')

    def test_launcher_restart_marker_takes_precedence_over_exit_code(self):
        self.make_venv(self.root)
        self.settings.update(restart=True, launch_exit=7)
        self.assertEqual(self.run_batch(self.root / 'comfyui.bat', answers='n\n'), 7, self.output)
        self.assertEqual((self.root / 'launch_count').read_text(), '2')

    def test_launcher_requirements_update(self):
        self.make_venv(self.root)
        self.settings['requirements_changed'] = True
        self.assertEqual(self.run_batch(self.root / 'comfyui.bat', answers='y\n'), 0, self.output)
        self.assertEqual(self.pip_installs(), [['-m', 'pip', 'install', '-r', 'requirements.txt']])

    def test_launcher_requirement_failure_does_not_launch(self):
        self.make_venv(self.root)
        self.settings.update(requirements_changed=True, fail='install -r requirements.txt')
        self.assertEqual(self.run_batch(self.root / 'comfyui.bat', answers='y\n'), 1, self.output)
        self.assertFalse(any(c['args'][:1] == ['main.py'] for c in self.calls))

    def test_launcher_empty_error_output_does_not_loop(self):
        self.settings['fail'] = '-m venv'
        self.assertEqual(self.run_batch(self.root / 'comfyui.bat', answers='n\n'), 1, self.output)

    def test_launcher_dirty_update_does_not_launch(self):
        self.settings['dirty'] = True
        self.assertEqual(self.run_batch(self.root / 'comfyui.bat', answers='y\n'), 1, self.output)
        self.assertFalse(any(c['args'][:1] == ['main.py'] for c in self.calls))

    def test_launcher_forwards_arguments(self):
        self.make_venv(self.root)
        self.assertEqual(self.run_batch(self.root / 'comfyui-start.bat', answers='n\n',
                                       script_args=('--output-directory', 'folder with spaces')), 0, self.output)
        launched = [c for c in self.calls if c['args'][:1] == ['main.py']]
        self.assertEqual(launched[0]['args'], ['main.py', '--windows-standalone',
                                              '--output-directory', 'folder with spaces'])

    def test_launcher_pip_installer_fallback(self):
        self.make_venv(self.root)
        self.settings['pip_missing'] = True
        self.assertEqual(self.run_batch(self.root / 'comfyui.bat', answers='n\n',
                                       extra_env={'PIP_INSTALLER_LOCATION': 'get-pip.py'}), 0, self.output)
        self.assertTrue(any(c['args'] == ['get-pip.py'] for c in self.calls))
