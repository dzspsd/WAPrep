# Exact Python selection on macOS and Windows

Build two standalone scripts that prompt for a full stable CPython version, defaulting to **3.11.1** (confirmed by the user), install it when needed, and replace the default command selection even when a newer Python already exists.

Use a private, checksum-pinned uv 0.12.19 bootstrap and its managed CPython catalog. This needs no preinstalled Python, Homebrew, winget, compiler, or package manager. The alternative of official installers introduces same-minor downgrade conflicts on Windows and privileged framework changes on macOS; source compilation introduces compiler and old-library dependencies. Managed distributions provide one exact-version mechanism across both systems.

## Supported outcome

- macOS: current user's Bash and Zsh defaults; native Intel and Apple Silicon. Install under `~/Library/Application Support/PythonSelector`. Configure startup files at their end, remove conflicting Python aliases/functions on startup, prepend the managed bin directory, and clear Python environment variables that can redirect the interpreter.
- Windows: Windows 10/11 with PowerShell 5.1 or newer, x64/x86/ARM64 as supported by the pinned catalog. Install in Program Files and prepend machine PATH (UAC/admin required). Configure the executing user's Windows PowerShell and PowerShell profiles, including VS Code and ISE hosts. Prefer native architecture; explicit x64 emulation on ARM64 is allowed only with a clear message when no native build exists.
- `python`, `python3`, `pip`, and `pip3` select the requested runtime. The separate Windows `py` launcher, absolute interpreter paths, explicit IDE settings, existing virtual environments, future environment activation, and arbitrary startup code are separate selection mechanisms and cannot be universally overridden by PATH.
- Existing OS/vendor/other Python installations remain installed. Default precedence changes; destructive uninstall is outside this task. A child script cannot alter an already-running parent shell; reopen terminals or source the generated activation file.
- Fail explicitly for an unavailable version or architecture; never silently substitute a different Python version. Pinning the bootstrap freezes the supported download catalog until maintained.

## Reliability

Validate exact `3.minor.patch` input before changes. Verify HTTPS bootstrap downloads against embedded SHA-256 values. Isolate uv from existing UV_* configuration, project pins, virtualenv/Conda and Python environment contamination. Reuse a healthy managed interpreter; reinstall a damaged managed interpreter once. Stage bin commands, check runtime version, SSL/sqlite imports, pip and venv before changing defaults. Retain backups; rollback profile, PATH and command changes on failure. Serialize concurrent runs. Provide an isolated mode for tests which never edits persistent user or machine configuration.

## Test strategy

Tests must exercise actual scripts and generated activation blocks. Test fresh installation, upgrade and downgrade, idempotence, already-selected version, conflicting aliases/functions/PATH entries, active virtualenv/Conda variables, poisoned uv settings, spaces/apostrophes in paths, invalid/unavailable versions, network failure, checksum failure, malformed profile markers, interrupted configuration, concurrent runs, and pip/venv runtime behavior. Run real downloads under a temporary root on this Mac. Run PowerShell helper tests on macOS; provide Windows native integration coverage in a GitHub Actions workflow. Distinguish local execution from CI that has merely been authored.
