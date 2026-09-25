# WAPrep — select an exact Python version

Two standalone installers prompt for a Python version, with **3.11.1** as the default. They download that exact CPython release when needed, configure command precedence, and verify Python, pip, SSL, SQLite and virtual environment creation. A newer installed version does not prevent a downgrade.

| Script | Platform | Configuration scope |
|---|---|---|
| [`setup-python-mac.sh`](setup-python-mac.sh) | Intel and Apple Silicon macOS; Bash/Zsh | Current user's shell defaults |
| [`setup-python-windows.ps1`](setup-python-windows.ps1) | Windows 10/11; PowerShell 5.1 or 7 | Machine PATH and executing user's PowerShell profiles |

No existing Python, Homebrew, winget, compiler or package manager is required. Internet access to GitHub and Astral's release downloads is required for uncached installs. Windows normal installation requests administrator permission through UAC.

## Run on a Mac

Download `setup-python-mac.sh`, open Terminal in its folder, and run:

```bash
bash setup-python-mac.sh
```

Press Enter for **3.11.1**, or type a full version such as `3.11.9`.

```bash
# Noninteractive choices:
bash setup-python-mac.sh --version 3.11.1
bash setup-python-mac.sh --yes
```

Run as your own user, without `sudo`. The script detects Intel (`x86_64`) or Apple Silicon (`arm64`), including an Apple Silicon Mac whose terminal runs under Rosetta. It installs in `~/Library/Application Support/PythonSelector`.

**Open a new terminal afterward**, or activate it immediately in Bash/Zsh:

```bash
source "$HOME/Library/Application Support/PythonSelector/activate.sh"
python --version
python3 --version
python -m pip --version
```

## Run on Windows

Download `setup-python-windows.ps1`, open PowerShell in its folder, and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup-python-windows.ps1
```

That execution policy option applies to this process. The installer does not permanently relax execution policy. Organization policy can still prevent scripts from running.

```powershell
# Noninteractive choices:
.\setup-python-windows.ps1 -Version 3.11.1
.\setup-python-windows.ps1 -Yes
```

Accept the UAC prompt using the **same Windows account**. If UAC switches to another administrator's account, the installer stops before changing defaults. Standard users who require different administrator credentials need an administrator-managed deployment; this script does not silently modify the wrong account.

Installation uses the protected `Program Files\PythonSelector` directory. The selected runtime is first in both machine and current-user PATH, ahead of older installations and Store aliases. PowerShell 5.1/7 console, ISE and VS Code host profiles receive a managed activation block.

**Completely close and reopen Windows Terminal and your IDE afterward.** If a parent application still retains the old PATH, sign out and back in. Then verify:

```powershell
python --version
python3 --version
python -m pip --version
where.exe python
```

Windows ARM64 uses a native build when available in the catalog. For old releases such as 3.11.1 it explicitly selects the **same version's x64 build**, requiring working Windows x64 emulation. Failure to execute that build stops configuration. x86 Windows uses the x86 catalog.

## What “override” means

`python`, `python3`, `pip`, and `pip3` use the requested version in the configured terminal environment. Existing OS, Homebrew, Conda and other Python installations remain installed. Deleting those installations can break unrelated software and is not necessary to replace the default commands.

The guarantee has practical boundaries:

- A script cannot modify an already-running parent terminal or IDE process. Activate explicitly or restart it.
- Existing virtual environments retain their own interpreters. Create a new environment with the selected Python. Activating a virtual environment afterward deliberately selects that environment.
- The separate Windows `py` launcher, explicit versioned commands, absolute interpreter paths, scheduled services, other users' shell aliases, Fish/custom shells, and IDE interpreter settings have independent selection rules.
- In VS Code, use **Python: Select Interpreter**, then choose the exact interpreter printed by `python -c "import sys; print(sys.executable)"`. An existing workspace interpreter or automatic virtualenv activation can take precedence over terminal defaults. Visual Studio and PyCharm also require selecting the interpreter in their settings.
- Arbitrary startup code can still redirect commands after activation. The tests cover ordinary PATH entries, aliases/functions, pyenv-like shims, inherited virtualenv/Conda variables and normal Bash/Zsh profiles.
- Unavailable releases/architectures, blocked downloads, insufficient permissions and incompatible operating systems fail with a nonzero exit. No different Python version is silently substituted.

Accepted inputs are full stable CPython versions from 3.8 onward **that exist for the target in the pinned catalog**. Partial versions, `latest`, prereleases and Python 2 are rejected. The requested default is the old 3.11.1 patch; the scripts honor that pin rather than upgrading it automatically.

## Reliability and recovery

- The private **uv 0.12.19** bootstrap is downloaded over HTTPS and verified against an embedded architecture-specific SHA-256. Python downloads use uv's catalog. This is a portable CPython distribution from `python-build-standalone`, not the python.org graphical installer.
- Existing `UV_*`, project configuration, `PYTHONHOME`, `PYTHONPATH` and active-environment variables cannot redirect installation or turn off uv's TLS checks.
- Healthy managed interpreters are reused. A damaged interpreter or failed runtime/pip/venv health check triggers one reinstall attempt.
- Runtime checks pass **before** defaults change. Concurrent runs are refused.
- Profile and environment backups are retained in the `run.*/backup` directory printed at completion. Catchable configuration failures roll back defaults and profile files. A force-kill, power loss, disk failure, or an externally changed/locked file can require manual recovery.
- Managed profile blocks are replaced, not duplicated. Broken markers fail safely. macOS dotfile symlinks are preserved. Windows UTF-8/UTF-16 profiles are supported; undecodable legacy ANSI files are refused with instructions to convert them, avoiding silent corruption.
- Windows preserves raw expandable PATH entries and registry value types. Interfering persistent `PYTHONHOME`, `PYTHONPATH`, `PYTHONSTARTUP`, and `PYTHONUSERBASE` values are backed up and removed for the machine and executing user. Other users' own values may still override machine defaults.

See [`docs/RECOVERY.md`](docs/RECOVERY.md) for restoring backed-up configuration.

## Test without changing your defaults

```bash
# macOS: explicit root required; no shell profiles are touched.
bash setup-python-mac.sh --version 3.11.1 --isolated --root "$PWD/python-test"
```

```powershell
# Windows: no elevation, persistent PATH, profiles, or registry changes.
.\setup-python-windows.ps1 -Version 3.11.1 -Isolated -InstallRoot "$PWD\python-test"
```

Isolated mode still downloads files into that root and verifies the real interpreter. Delete the test directory afterward when its Python processes have exited.

## Run the test suite

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tests/integration_mac.py
```

```powershell
./tests/test_windows.ps1
./tests/integration_windows.ps1
```

Python is a **developer test dependency**, not an installer prerequisite. The Windows helper tests also run in PowerShell 7 on macOS/Linux; native installation tests require Windows.

[`test.yml`](.github/workflows/test.yml) runs real installs on Apple Silicon macOS, Intel macOS, Windows PowerShell 5.1 and Windows PowerShell 7. Its Windows machine-configuration tests are restricted to disposable GitHub Actions runners. The suites cover upgrades/downgrades, repeat runs, conflicting configurations, unavailable releases, failed downloads, corrupted runtime recovery, locking, profile preservation and rollback. See [`TEST_REPORT.md`](TEST_REPORT.md) for results and limits.

## Maintenance

Available Python downloads are frozen in the pinned uv release. To support a newer release absent from its catalog, update the uv version **and all five bootstrap checksums** together, then rerun the full matrix. Download hashes must come from the matching upstream release assets.

References: [uv Python versions](https://docs.astral.sh/uv/concepts/python-versions/), [uv releases](https://github.com/astral-sh/uv/releases), [PowerShell profile behavior](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles), [Python 3.11.1 release](https://www.python.org/downloads/release/python-3111/).
