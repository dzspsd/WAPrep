"""Behavioral tests: no downloads or changes to the real user's defaults."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'setup-python-mac.sh'


class MacHelpers(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="python selector ' tests ")
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def bash(self, code, *args, check=True):
        result = subprocess.run(['/bin/bash', '-c',
                                 'source "$1"; shift; ' + code, 'test', str(SCRIPT), *map(str, args)],
                                text=True, capture_output=True)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_scripts_exist(self):
        self.assertTrue(SCRIPT.is_file(), 'macOS installer must exist')

    def test_exact_version_validation(self):
        for version in ('3.11.1', '3.13.12', '3.9.0'):
            with self.subTest(version=version):
                self.bash('validate_version "$1"', version)
        for version in ('3.1.1', '3.11', 'latest', '3.11.1;id', '03.11.1', '3.11.01',
                        '2.7.18', '3.14.0rc1', '', '3.999.999'):
            with self.subTest(version=version):
                self.assertNotEqual(self.bash('validate_version "$1"', version, check=False).returncode, 0)

    def test_profile_preserved_replaced_once_and_at_end(self):
        profile = self.root / '.zshrc'
        block = self.root / 'block'
        profile.write_text('# my settings\nexport FRIENDLY="café"\n')
        block.write_text('echo first\n')
        self.bash('write_profile "$1" "$2"', profile, block)
        with profile.open('a') as f:
            f.write('echo later\n')
        block.write_text('echo second\n')
        self.bash('write_profile "$1" "$2"', profile, block)
        text = profile.read_text()
        self.assertIn('export FRIENDLY="café"', text)
        self.assertNotIn('echo first', text)
        self.assertEqual(text.count('# >>> PythonSelector >>>'), 1)
        self.assertGreater(text.index('echo second'), text.index('echo later'))

    def test_malformed_profile_is_not_modified(self):
        for text in ('before\n# >>> PythonSelector >>>\nunfinished\n',
                     '# <<< PythonSelector <<<\n',
                     '# >>> PythonSelector >>>\n# >>> PythonSelector >>>\n# <<< PythonSelector <<<\n'):
            profile = self.root / '.bashrc'
            block = self.root / 'block'
            profile.write_text(text)
            block.write_text('new\n')
            self.assertNotEqual(self.bash('write_profile "$1" "$2"', profile, block, check=False).returncode, 0)
            self.assertEqual(profile.read_text(), text)

    def test_activation_overrides_alias_function_path_and_pythonhome(self):
        bindir = self.root / 'current' / 'bin'
        bindir.mkdir(parents=True)
        python = bindir / 'python'
        python.write_text('#!/bin/sh\nprintf "selected:%s\\n" "$*"\n')
        python.chmod(0o755)
        activate = self.root / 'activate.sh'
        self.bash('make_activation "$1" "$2"', self.root, activate)
        code = 'python() { echo wrong; }; alias python3=false; export PYTHONHOME=/bad; . "$1"; . "$1"; python "hello world"; test -z "${PYTHONHOME-}"; printf "%s" "$PATH"'
        for shell in ('/bin/bash', '/bin/zsh'):
            if Path(shell).exists():
                result = subprocess.run([shell, '-c', code, 'test', str(activate)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(result.stdout.startswith('selected:hello world\n'), result.stdout)
                self.assertEqual(result.stdout.count(str(bindir)), 1)

    def test_profile_symlink_kept(self):
        target = self.root / 'dotfiles-zshrc'
        target.write_text('echo keep\n')
        profile = self.root / '.zshrc'
        profile.symlink_to(target)
        block = self.root / 'block'
        block.write_text('echo configured\n')
        self.bash('write_profile "$1" "$2"', profile, block)
        self.assertTrue(profile.is_symlink())
        self.assertIn('echo configured', target.read_text())

    def test_hash_mismatch_rejected(self):
        asset = self.root / 'download'
        asset.write_bytes(b'corrupt archive')
        result = self.bash('verify_sha256 "$1" "$2"', asset, '0' * 64, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checksum', result.stderr.lower())

    def test_broken_symlink_backup_cannot_poison_rollback(self):
        broken = self.root / 'broken-profile'
        broken.symlink_to(self.root / 'missing-target')
        result = self.bash('set -u; snapshot="$1"; saved_paths=(); saved_exists=(); '
                           'save_file "$2" || :; test "${#saved_paths[@]}" -eq 0 && '
                           'test "${#saved_exists[@]}" -eq 0', self.root, broken, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cli_invalid_version_no_installation(self):
        dest = self.root / 'install'
        result = subprocess.run(['/bin/bash', str(SCRIPT), '--version', '3.11;id',
                                 '--root', str(dest), '--isolated'], text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(dest.exists())


if __name__ == '__main__':
    unittest.main()
