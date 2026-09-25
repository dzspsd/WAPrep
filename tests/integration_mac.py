"""Real macOS installations in temporary directories; never uses the real HOME.

Run: python3 tests/integration_mac.py
Requires internet for two exact CPython releases and pinned uv.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-python-mac.sh'
checks = []


def run(args, env, expected=0, input=None):
    result = subprocess.run(args, env=env, input=input, text=True, capture_output=True, timeout=180)
    if (expected == 0 and result.returncode != 0) or (expected != 0 and result.returncode == 0):
        raise AssertionError(f'{args}: exit {result.returncode}\n{result.stdout}\n{result.stderr}')
    return result


def checked(name):
    checks.append(name)
    print('PASS ' + name, flush=True)


def main():
    if sys.platform != 'darwin':
        raise SystemExit('This integration suite requires macOS.')
    with tempfile.TemporaryDirectory(prefix="python-selector space's ") as temp:
        base = Path(temp)
        root = base / 'managed'
        home = base / 'home'
        home.mkdir()
        env = dict(os.environ, HOME=str(home), ZDOTDIR=str(home), PATH='/usr/bin:/bin:/usr/sbin:/sbin')
        env.pop('PYTHONHOME', None)
        env.pop('PYTHONPATH', None)
        args = ['/bin/bash', str(SCRIPT), '--root', str(root)]

        def install(version, isolated=True, extra_env=None, expected=0, stdin=None):
            cmd = args + (['--version', version] if version else []) + (['--isolated'] if isolated else [])
            return run(cmd, dict(env, **(extra_env or {})), expected, stdin)

        def verify(version):
            for name in ('python', 'python3'):
                result = run([str(root / 'current/bin' / name), '-c',
                              'import platform,sys,ssl,sqlite3; print(platform.python_version()); print(sys.executable)'], env)
                assert result.stdout.splitlines()[0] == version, result.stdout
                assert f'cpython-{version}-' in result.stdout, result.stdout
            for name in ('pip', 'pip3'):
                result = run([str(root / 'current/bin' / name), '--version'], env)
                assert f'cpython-{version}-' in result.stdout, result.stdout
            venv = base / ('venv-' + str(len(checks)))
            run([str(root / 'current/bin/python'), '-m', 'venv', str(venv)], env)
            result = run([str(venv / 'bin/python'), '-c', 'import platform; print(platform.python_version())'], env)
            assert result.stdout.strip() == version
            run([str(venv / 'bin/python'), '-m', 'pip', '--version'], env)
            shutil.rmtree(venv)

        install(None, stdin='\n')
        verify('3.11.1')
        checked('interactive blank input installs exact default 3.11.1, pip and working venv')
        assert not any(home.iterdir()), list(home.iterdir())
        checked('isolated mode leaves test HOME untouched')

        target = root / 'current/bin/python'
        runtime = run([str(target), '-c', 'import sys; print(sys.executable)'], env).stdout.strip()
        before = Path(runtime).stat().st_mtime_ns
        install('3.11.1')
        assert Path(runtime).stat().st_mtime_ns == before
        verify('3.11.1')
        checked('repeat run reuses the existing exact interpreter')

        install('3.11.9')
        verify('3.11.9')
        checked('upgrade from 3.11.1 to 3.11.9')
        install('3.11.1')
        verify('3.11.1')
        checked('downgrade from 3.11.9 to exactly 3.11.1 despite uv minor alias')

        install('3.11.1', extra_env={'UV_OFFLINE':'1', 'UV_PYTHON_INSTALL_DIR':'/bad',
                'UV_PYTHON_INSTALL_MIRROR':'https://invalid.example', 'UV_PYTHON':'3.99.99',
                'UV_CONFIG_FILE':'/does/not/exist', 'PYTHONHOME':'/bad', 'PYTHONPATH':'/bad',
                'VIRTUAL_ENV':'/bad', 'CONDA_PREFIX':'/bad'})
        verify('3.11.1')
        checked('poisoned UV/PYTHON/virtualenv/Conda environment cannot change target')

        previous_link = os.readlink(root / 'current')
        result = install('3.99.99', expected=1)
        assert os.readlink(root / 'current') == previous_link
        verify('3.11.1')
        checked('unavailable version fails and leaves previous default working')

        result = install('3.12.1', extra_env={'HTTPS_PROXY':'http://127.0.0.1:9','HTTP_PROXY':'http://127.0.0.1:9','ALL_PROXY':'http://127.0.0.1:9','NO_PROXY':''}, expected=1)
        assert os.readlink(root / 'current') == previous_link
        checked('failed runtime download leaves previous default working')

        lock = root / '.lock'
        lock.mkdir()
        (lock / 'pid').write_text(str(os.getpid()))
        result = install('3.11.1', expected=1)
        assert 'Another run' in result.stderr
        assert lock.exists()
        shutil.rmtree(lock)
        checked('concurrent installation refused without deleting existing lock')

        # Populate realistic Bash/Zsh startup files, including an older Python,
        # a pyenv-like shim directory, aliases and shell functions.
        fakebin = base / 'old-python-bin'
        fakebin.mkdir()
        fake = fakebin / 'python'
        fake.write_text('#!/bin/sh\necho old-python\n')
        fake.chmod(0o755)
        startup = f'export PATH="{fakebin}:$PATH"\nexport PYTHONHOME=/wrong\n'
        (home / '.profile').write_text(startup + 'export ORIGINAL_PROFILE_WAS_LOADED=yes\n')
        (home / '.bashrc').write_text(startup + 'python() { echo function-wrong; }\n')
        (home / '.zshrc').write_text(startup + 'alias python=echo\npython3() { echo function-wrong; }\n')
        install('3.11.1', isolated=False)
        assert not (home / '.bash_profile').exists(), 'Must not hide existing .profile'
        command = "python -c 'import platform; print(\"SELECTED=\"+platform.python_version())'; python3 --version; pip --version"
        for shell, flags in (('/bin/zsh','-lic'),('/bin/zsh','-ic'),('/bin/bash','-lic'),('/bin/bash','-ic')):
            result = run([shell, flags, command], env)
            assert 'SELECTED=3.11.1' in result.stdout, result.stdout + result.stderr
        result = run(['/bin/bash','-lc','printf "%s" "$ORIGINAL_PROFILE_WAS_LOADED"'], env)
        assert result.stdout == 'yes', result.stdout
        checked('fresh Bash/Zsh login and interactive shells override old PATH, aliases and functions')
        checked('existing .profile remains the Bash login profile')

        install('3.11.1', isolated=False)
        for file in ('.profile','.bashrc','.zprofile','.zshrc','.zlogin'):
            assert (home / file).read_text().count('# >>> PythonSelector >>>') == 1
        checked('persistent configuration is idempotent without duplicate blocks')

        (home / '.zlogin').write_text('# >>> PythonSelector >>>\nbroken\n')
        original = {p: p.read_bytes() for p in home.iterdir() if p.is_file()}
        original_activate = (root / 'activate.sh').read_bytes()
        previous_link = os.readlink(root / 'current')
        result = install('3.11.9', isolated=False, expected=1)
        assert 'restoring' in result.stderr
        assert original == {p: p.read_bytes() for p in home.iterdir() if p.is_file()}
        assert original_activate == (root / 'activate.sh').read_bytes()
        assert os.readlink(root / 'current') == previous_link
        verify('3.11.1')
        checked('mid-configuration failure restores previous commands and every profile byte')

        (home / '.zlogin').unlink()
        (home / '.zlogin').symlink_to(home / 'absent-profile')
        original = {p: p.read_bytes() for p in home.iterdir() if p.is_file()}
        result = install('3.11.9', isolated=False, expected=1)
        assert 'Broken configuration symlink' in result.stderr
        assert 'unbound variable' not in result.stderr
        assert os.readlink(root / 'current') == previous_link
        assert original == {p: p.read_bytes() for p in home.iterdir() if p.is_file()}
        checked('broken later profile symlink triggers complete rollback')

        runtime = Path(run([str(target), '-c', 'import sys; print(sys.executable)'], env).stdout.strip())
        runtime.unlink()
        install('3.11.1')
        verify('3.11.1')
        checked('missing managed executable is repaired automatically')

        ssl_module = Path(run([str(target), '-c', 'import ssl; print(ssl.__file__)'], env).stdout.strip())
        ssl_module.unlink()
        install('3.11.1')
        verify('3.11.1')
        checked('damaged SSL module triggers complete runtime repair')
        previous_link = os.readlink(root / 'current')

        # Invalid CLI paths/versions must fail before installing anything.
        for version in ('3.11','3.11.1; touch /tmp/unwanted','3.1.1'):
            install(version, expected=1)
        assert os.readlink(root / 'current') == previous_link
        checked('invalid versions fail without changing the selection')

    print(json.dumps({'platform':sys.platform,'passed':len(checks),'checks':checks}, indent=2))


if __name__ == '__main__':
    main()
