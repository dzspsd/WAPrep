# Verification record

## Local verification

Executed on an Apple Silicon Mac with macOS 27.0, the built-in Bash 3.2, Zsh, Python 3.9.6 as the test harness, and a private PowerShell 7.6.6 runtime.

- **9 macOS helper tests passed.** Exact input validation, command precedence, quoting, PATH deduplication, profile preservation and marker validation, symlink handling, checksum rejection, and backup-registration failure.
- **17 real macOS integration checks passed.** Actual downloads of 3.11.1 and 3.11.9; interactive default; pip and venv; isolated HOME preservation; reuse; upgrade; exact downgrade; contaminated environments; unavailable releases; failed network downloads; concurrent locks; fresh Bash/Zsh login/interactive shells; `.profile` precedence; idempotent configuration; partial-write rollback; broken-symlink rollback; missing-executable repair; damaged SSL repair; invalid inputs.
- **10 portable PowerShell helper tests passed.** Input, PATH, Unicode and legacy profile encoding, marker preservation, activation, architecture mapping, checksum rejection, environment cleanup/restoration, and file backup recovery.
- Bash syntax, Python test compilation and PowerShell AST parsing passed.
- An independent read-only review identified recovery, encoding, PowerShell 5.1 and UAC-account edge cases. Regression tests and fixes were applied.

Local testing did not change the real user's Python defaults, shell profiles, or machine PATH. Downloads and configuration integration tests used disposable directories and a temporary HOME.

## Native CI

**All four native jobs passed** in [GitHub Actions run 36096642695](https://github.com/dzspsd/WAPrep/actions/runs/36096642695), testing source revision [`8d2d763`](https://github.com/dzspsd/WAPrep/commit/8d2d763c132b3c6e5d01298e16c36019f9a46d92).

| Environment | Helper tests | Real integration checks | Result |
|---|---:|---:|---|
| macOS 15, Apple Silicon (`macos-15`) | 9 | 17 | Passed |
| macOS 15, Intel (`macos-15-intel`) | 9 | 17 | Passed |
| Windows Server 2025 x64, Windows PowerShell 5.1 | 10 | 11 | Passed |
| Windows Server 2025 x64, PowerShell 7 | 10 | 11 | Passed |

Windows native checks execute actual downloaded Python binaries and fresh PowerShell/cmd sessions. They verify install/reuse, upgrade/downgrade, inherited configuration isolation, unavailable releases, locking, damaged-interpreter and missing-pip recovery, machine/user PATH precedence, preservation of raw expandable registry values, repeated installation, and rollback after a malformed profile interrupts configuration. The 94 named tests/check groups across the four jobs include additional assertions inside each group.

CI found and drove a production regression fix for modern PowerShell leaving empty environment values when given a null string. It also exposed two test/workflow issues (dynamic `shell` expressions and PowerShell 5.1 command quoting), which were corrected before the final green run. The commit recording this report changes documentation only; installer and test code remain identical to the tested source revision.

Windows UAC's interactive approval UI, Windows ARM64/x86 hardware, individual Windows 10/11 desktop images, enterprise policy, custom shells, and IDE interpreter-selection UI were not exercised. GitHub's Windows runners run elevated, so CI verifies native machine configuration but not an interactive UAC prompt. The macOS installer was exercised on physical Apple Silicon locally and on both GitHub-hosted Mac architectures.
