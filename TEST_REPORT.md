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

The repository workflow runs the complete scripts on Intel and ARM macOS, Windows PowerShell 5.1, and Windows PowerShell 7. Results will be recorded after the initial repository push.

Windows UAC's interactive approval UI, Windows ARM64/x86 hardware, enterprise policy, custom shells, and IDE interpreter-selection UI are not exercised by the local tests. GitHub's Windows runners run elevated, so CI can verify native machine configuration but not an interactive UAC prompt.
