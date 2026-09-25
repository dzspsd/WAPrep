# Recovering configuration

The scripts print a backup directory. Keep it until you have checked new terminals and IDEs. A successful reinstall with another exact version is the easiest way to change Python again.

These backups restore configuration; they do not uninstall downloaded runtimes, remove installed packages, terminate running processes, or recreate a damaged operating-system Python.

## macOS

Each `run.*/backup` contains:

- `files.tsv`: whether each file existed and its original path. Numbered backup files correspond to rows, starting at `0`.
- `previous-current.txt`: the previous generation selected by the `current` symlink (empty on first install).

Restore numbered file contents to the matching paths. If the row starts with `no`, the installer created that file; remove it only if you have not made subsequent changes. Write through existing dotfile symlinks instead of replacing them. Restore the `current` link to `previous-current.txt`, or remove it if there was no previous generation. Open a new shell afterward.

A stale `.lock` directory is possible after SIGKILL or power loss. Read `.lock/pid` and confirm that no installer is running before removing the lock directory. Never remove an active installer's lock.

## Windows

Normal mode backups are beneath `Program Files\PythonSelector\run.*\backup`. Open PowerShell **as the same administrator account used for installation**. Review the specific backup before restoring it; newer changes made since that backup will be overwritten.

Dot-source the installer to load recovery functions without running installation:

```powershell
. .\setup-python-windows.ps1
$backup = 'C:\Program Files\PythonSelector\run.REPLACE_WITH_RUN_ID\backup'
$files = @(Get-Content -LiteralPath (Join-Path $backup 'files.json') -Raw | ConvertFrom-Json)
$environment = @(Get-Content -LiteralPath (Join-Path $backup 'environment.json') -Raw | ConvertFrom-Json)
Restore-ConfigFiles $files
foreach ($entry in $environment) { Set-EnvironmentEntry $entry }
Send-EnvironmentNotification
```

Restart terminals and IDEs, or sign out and back in. In isolated mode the environment backup is empty and the files affect only the test installation.

The Windows `.lock` file may remain on disk normally. The installer uses an exclusive open handle; its presence alone does not mean another run is active. Windows releases the lock if the process exits.
