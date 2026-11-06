"""Hermetic selector/runner checks: tiny local Git repos, never real builds or services."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

RUNNER = Path(__file__).resolve().parents[2] / 'scripts/tests-for.sh'


class RunnerChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='chatterbox-tests-for-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        shutil.copy2(RUNNER, self.root / 'scripts/tests-for.sh')
        self.git('init', '-q')
        self.config(self.root)
        (self.root / '.gitignore').write_text('build/\ntrace\nCore/\n')
        self.parent_file = self.write('Chatterbox/Engine/Parent.swift', 'struct ParentProbe {}\n')
        self.write('scripts/test-map.txt', '\n'.join([
            'Chatterbox/Engine/Parent.swift test-parent.sh',
            'Chatterbox/Engine/Renamed.swift test-extra.sh',
            'Chatterbox/Engine/space* test-space.sh',
            'Core/Shared/Changed.swift test-core.sh',
            'Core/Shared/Unrelated.swift test-extra.sh',
        ]) + '\n')
        for name in ('parent', 'extra', 'space', 'core'):
            self.script('test-' + name)
        self.script('check-sources')
        self.without_core = self.commit()
        self.core = self.root / 'Core'
        self.core.mkdir()
        self.git('init', '-q', cwd=self.core)
        self.config(self.core)
        self.write('Core/Shared/Changed.swift', 'struct CoreProbe {}\n')
        self.write('Core/Shared/Unrelated.swift', 'struct OtherProbe {}\n')
        self.core_base = self.commit(self.core)
        self.link_core(self.core_base)
        self.base = self.commit()
        self.pushed()

    def config(self, cwd):
        self.git('config', 'user.name', 'Fixture', cwd=cwd)
        self.git('config', 'user.email', 'fixture@example.invalid', cwd=cwd)
        self.git('config', 'commit.gpgsign', 'false', cwd=cwd)
        self.git('config', 'core.hooksPath', '/dev/null', cwd=cwd)

    def git(self, *args, cwd=None):
        return subprocess.check_output(['git', *args], cwd=cwd or self.root, text=True, stderr=subprocess.PIPE).strip()

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def script(self, name, code=0, mark=None):
        # All values are fixture constants, not shell text received from users.
        body = '#!/bin/sh\n'
        if mark:
            body += f"printf '%s\\n' '{mark}' >> trace\nprintf '%s\\n' '{mark}'\n"
        body += f'exit {code}\n'
        p = self.write('scripts/' + name + '.sh', body)
        p.chmod(0o755)

    def commit(self, cwd=None):
        self.git('add', '-A', cwd=cwd)
        self.git('commit', '-qm', 'fixture', cwd=cwd)
        return self.git('rev-parse', 'HEAD', cwd=cwd)

    def link_core(self, sha):
        self.git('update-index', '--add', '--cacheinfo', '160000,' + sha + ',Core')

    def pushed(self):
        for cwd in (self.root, self.core):
            self.git('update-ref', 'refs/remotes/origin/main', self.git('rev-parse', 'HEAD', cwd=cwd), cwd=cwd)

    def run_runner(self, *args):
        return subprocess.run(['./scripts/tests-for.sh', *args], cwd=self.root, capture_output=True, text=True)

    def selection(self, *args):
        r = self.run_runner(*args)
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        return set(r.stdout.splitlines())

    def test_committed_pushed_parent_and_core_use_requested_gitlink(self):
        self.parent_file.write_text('struct ParentProbe { var changed = true }\n')
        self.write('Core/Shared/Changed.swift', 'struct CoreProbe { var changed = true }\n')
        self.link_core(self.commit(self.core))
        self.commit()
        self.pushed()
        self.assertEqual(self.selection(), set(), 'default remains compatible on clean pushed main')
        self.assertEqual(self.selection('--since', self.base), {'scripts/test-parent.sh', 'scripts/test-core.sh'})

    def test_dirty_staged_untracked_and_unicode_paths(self):
        self.parent_file.write_text('struct ParentProbe { var dirty = true }\n')
        self.git('add', str(self.parent_file.relative_to(self.root)))
        self.write('Chatterbox/Engine/space 雪.swift', 'struct NewProbe {}\n')
        self.write('Core/Shared/Changed.swift', 'struct CoreProbe { var dirty = true }\n')
        self.assertEqual(self.selection('--since', self.base), {
            'scripts/check-sources.sh', 'scripts/test-parent.sh', 'scripts/test-space.sh', 'scripts/test-core.sh'})
        self.assertEqual(self.selection(), self.selection('--since', self.base))

    def test_rename_selects_old_and_new_paths(self):
        self.git('mv', 'Chatterbox/Engine/Parent.swift', 'Chatterbox/Engine/Renamed.swift')
        self.commit()
        self.assertEqual(self.selection('--since', self.base), {
            'scripts/check-sources.sh', 'scripts/test-parent.sh', 'scripts/test-extra.sh'})

    def test_new_core_since_baseline_selects_all_its_sources(self):
        self.assertEqual(self.selection('--since', self.without_core), {
            'scripts/check-sources.sh', 'scripts/test-core.sh', 'scripts/test-extra.sh'})

    def test_missing_history_or_checkout_cannot_be_empty_success(self):
        r = self.run_runner('--since', 'missing-fixture-revision')
        self.assertEqual(r.returncode, 2)
        self.assertIn('cannot inspect', r.stderr)
        self.link_core('f' * 40)
        self.git('commit', '-qm', 'fixture with unavailable Core history')
        missing = self.git('rev-parse', 'HEAD')
        r = self.run_runner('--since', missing)
        self.assertEqual(r.returncode, 2)
        self.assertIn('cannot inspect Core', r.stderr)
        self.core.rename(self.root / 'UnavailableCore')
        r = self.run_runner('--since', self.base)
        self.assertEqual(r.returncode, 2)
        self.assertIn('initialize its checkout', r.stderr)

    def test_file_arguments_and_flags_can_be_interleaved(self):
        r = self.run_runner('Chatterbox/Engine/Parent.swift', '--why', 'Core/Shared/Changed.swift')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('scripts/test-parent.sh', r.stdout)
        self.assertIn('scripts/test-core.sh', r.stdout)

    def test_invalid_combinations_and_unknown_flags(self):
        for args in [('--fail-fast',), ('--since', self.base, '--all'),
                     ('--since', self.base, 'README.md'), ('--unknown-fixture-option',)]:
            with self.subTest(args=args):
                self.assertEqual(self.run_runner(*args).returncode, 2)

    def prepare_run(self):
        self.script('test-a-pass', mark='first')
        self.script('test-b-fail', code=7, mark='failure')
        self.script('test-c-after', mark='after')
        return len(self.selection('--all'))

    def test_fail_fast_stops_and_preserves_failure_log(self):
        total = self.prepare_run()
        r = self.run_runner('--run', '--all', '--fail-fast')
        self.assertEqual(r.returncode, 1)
        self.assertEqual((self.root / 'trace').read_text().splitlines(), ['first', 'failure'])
        self.assertIn(f'1 passed, 1 failed, {total - 2} not run', r.stdout)
        self.assertIn('remaining checks are NOT verified', r.stdout)
        self.assertEqual((self.root / 'build/test-logs/test-b-fail.log').read_text().strip(), 'failure')
        self.assertFalse((self.root / 'build/test-logs/test-c-after.log').exists())

    def test_default_run_continues_and_returns_failure(self):
        total = self.prepare_run()
        r = self.run_runner('--run', '--all')
        self.assertEqual(r.returncode, 1)
        self.assertEqual((self.root / 'trace').read_text().splitlines(), ['first', 'failure', 'after'])
        self.assertIn(f'{total - 1} passed, 1 failed, 0 not run', r.stdout)

    def test_success_and_empty_run_report_no_unrun_checks(self):
        r = self.run_runner('--run', '--all', '--fail-fast')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('0 failed, 0 not run', r.stdout)
        r = self.run_runner('--run', '--since', self.base, '--fail-fast')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('nothing changed', r.stderr)
        self.assertEqual(r.stdout, '')


if __name__ == '__main__':
    unittest.main()
