"""Test-only executable dispatcher. Never invokes pip, Git, curl, or a GPU."""
import json
import os
from pathlib import Path
import shutil
import sys


def main():
    args = sys.argv[1:]
    exe = Path(sys.argv[0])
    name = exe.stem.lower()
    settings = json.loads(os.environ.get('STUB_SETTINGS', '{}'))
    root = Path(os.environ['STUB_ROOT']).resolve()
    with (root / 'calls.jsonl').open('a', encoding='utf-8') as log:
        log.write(json.dumps({'exe': str(exe), 'args': args, 'cwd': os.getcwd()}) + '\n')
    joined = ' '.join(args)
    if settings.get('fail') and settings['fail'] in joined:
        return 1
    if name == 'where':
        return int(args[0] in settings.get('missing', []))
    if name == 'nvidia-smi':
        print(settings.get('driver', '581.80'))
        return 0
    if name == 'git':
        directory = Path(args[1]) if args[:1] == ['-C'] else Path.cwd()
        if args[0] == 'clone':
            directory = Path(args[-1])
            directory.mkdir(parents=True)
            (directory / 'requirements.txt').write_text('torchaudio\n', encoding='utf-8')
            (directory / '.git').mkdir()
        elif '--show-toplevel' in args:
            print(root if settings.get('wrong_repo') else directory)
        elif 'get-url' in args:
            print('https://github.com/Comfy-Org/' + directory.name + '.git')
        elif 'rev-parse' in args:
            print('a' * 40)
        elif 'diff' in args:
            if 'requirements.txt' in args:
                return int(settings.get('requirements_changed', False))
            return int(settings.get('dirty', False))
        return 0
    if name == 'curl':
        target = Path(args[args.index('--output') + 1])
        launcher = args[-1].rsplit('/', 1)[-1]
        data = (Path(os.environ['STUB_SOURCE']) / launcher).read_bytes()
        if settings.get('bad_download'):
            data = b'<html>not a launcher</html>'
        target.write_bytes(data)
        return int(settings.get('download_failure', False))
    if name == 'py':
        if settings.get('missing_python') or settings.get('no_py'):
            return 1
        print(root / 'bin' / 'python.exe')
        return 0
    if name == 'python':
        return python_call(args, exe, root, settings)
    raise RuntimeError(f'Unexpected test executable: {exe}')


def python_call(args, exe, root, settings):
    if settings.get('missing_python'):
        return 1
    if args[:2] == ['-m', 'venv']:
        scripts = Path(args[2]) / 'Scripts'
        scripts.mkdir(parents=True)
        shutil.copyfile(root / 'bin' / 'python.exe', scripts / 'python.exe')
        (scripts / 'activate.bat').write_text('@echo off\nexit /b 0\n')
        return 0
    if args[:2] == ['-m', 'pip']:
        if settings.get('pip_missing') and not (root / 'pip_ready').exists():
            return 1
        if settings.get('fail_pip_check') and args[2:] == ['check']:
            return 1
        return 0
    if args == ['get-pip.py']:
        (root / 'pip_ready').touch()
        return 0
    if args[:1] == ['main.py']:
        marker = root / 'launch_count'
        count = int(marker.read_text()) + 1 if marker.exists() else 1
        marker.write_text(str(count))
        restart = Path(os.environ['COMFYUI_RESTART'])
        if settings.get('restart') and count == 1:
            restart.touch()
        else:
            restart.unlink(missing_ok=True)
        return settings.get('launch_exit', 0)
    if args[:1] != ['-c']:
        raise RuntimeError(f'Unexpected Python arguments: {args}')
    code = args[1]
    if code == 'import sys; print(sys.executable)':
        print(exe)
        return 0
    if 'import torch' in code:
        return int(settings.get('bad_core', False))
    if 'import triton' in code:
        if 'importlib.metadata' in code:
            return 0 if settings.get('existing_triton') else 1
        return 0
    if 'importlib.import_module' in code:
        return int(settings.get('bad_import') == args[-1])
    # Run the real validation and file-handling snippets with controlled Python facts.
    import platform
    import struct
    import sysconfig
    if 'sys.version_info' in code:
        sys.version_info = tuple(settings.get('python_version', [3, 13, 13]))
    if 'platform.machine' in code:
        platform.machine = lambda: settings.get('machine', 'AMD64')
        struct.calcsize = lambda _: settings.get('pointer_size', 8)
    if 'Py_GIL_DISABLED' in code:
        sysconfig.get_config_var = lambda _: settings.get('free_threaded', 0)
    sys.argv = ['-c', *args[2:]]
    exec(code, {'__name__': '__main__'})
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
