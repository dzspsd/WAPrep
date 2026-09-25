# Python Selector Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task.

**Goal:** Deliver two standalone exact-version Python installer scripts with reproducible tests and clear usage instructions.

**Architecture:** Private pinned uv downloads exact CPython builds. Verified staged commands become the default only after the runtime passes checks; backed-up shell/PATH changes are rolled back on errors.

**Tech stack:** macOS Bash 3.2, Windows PowerShell 5.1+, Python unittest for shell orchestration, standalone PowerShell assertions, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-24-python-selector-design.md`

## Global constraints

- Default version is 3.11.1; no silently substituted patch versions.
- End users need no existing Python installation or package manager.
- Do not delete third-party or operating-system Python installations.
- All local integration installs use isolated temporary roots.
- This directory is not a Git repository; no commits or worktrees are required.

## Review focus

- User and machine PATH precedence on Windows, including Store aliases.
- Profile encoding, duplicate/malformed markers, and command injection through paths.
- Failed installs leave the previous default usable; backups remain recoverable.
- Active environments, project configuration, and inherited environment variables.
- Actual architecture availability and exact runtime identity on upgrade/downgrade.

## Tasks

1. Write and run failing behavioral tests for version validation, managed-profile replacement, activation precedence, bootstrap hashes and transaction rollback. Tests assert user-visible filesystem and subprocess results, not implementation text.
2. Implement `setup-python-mac.sh`; execute unit tests and real isolated downloads of 3.11.1 and a newer patch, then downgrade. Verify `python`, `python3`, pip and venv and a fresh Bash/Zsh with conflicting profile configuration.
3. Write Windows PowerShell tests first, then implement `setup-python-windows.ps1`. Execute portable PowerShell tests locally for input, path, profile and environment behavior. Author native Windows integration tests for actual executable selection, persistent machine PATH, upgrade/downgrade and rollback.
4. Review both scripts independently using the code review skill while completing README, test report and CI configuration. Fix substantive findings with regression tests, rerun all local tests, and distinguish tested platforms from unexecuted CI.

## Progress

- Design: confirmed default 3.11.1. Native script development and isolated tests are authorized by the request; no production defaults will be changed during development.
- Research: pinned uv supports 3.11.1 on Intel/ARM macOS and x86/x64 Windows. Native Windows ARM64 availability must be checked per version.
- Implementation: both standalone scripts, helper tests, real integration suites, recovery documentation and CI workflow are complete.
- Review: corrected incomplete backup registration, unavailable damaged-interpreter discovery, legacy profile decoding, native PowerShell stderr handling, and cross-account UAC behavior.
- Native CI finding: modern PowerShell needs explicit environment-variable removal; assigning a null string can leave an empty environment value. Added a failing regression test and fixed the removal operation.
- Test harness findings: corrected GitHub Actions shell expression usage and Windows PowerShell 5.1 nested command quoting.
- User-authorized scope extension: initialized this directory as a repository, created private `dzspsd/WAPrep`, and pushed the implementation and test workflow.
