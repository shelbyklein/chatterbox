"""Exercise real delivery scripts with system/install commands intercepted."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
STUB = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'rm' and all(not a.startswith('/Applications') for a in args):
    import shutil
    for a in args:
        if a.startswith('-'): continue
        p = Path(a).resolve()
        assert p.is_relative_to(Path.cwd()), p
        if p.is_dir(): shutil.rmtree(p)
        else: p.unlink(missing_ok=True)
    sys.exit(0)
with open('events.jsonl', 'a') as f:
    f.write(json.dumps([name, args, Path('build/DerivedData.building').exists(),
                       os.environ.get('CHATTERBOX_DATA_DIR')]) + '\n')
if name == 'git':
    if args[:2] == ['branch', '--show-current']: print(os.environ.get('BRANCH', 'main'))
    elif args[:2] == ['diff', '--quiet']: sys.exit(int(os.environ.get('DIRTY', '0')))
    elif args[:3] == ['diff', '--cached', '--quiet']: sys.exit(int(os.environ.get('STAGED', '0')))
    elif args[:1] == ['rev-parse']: print('fixture')
    elif args[:1] == ['push'] and os.environ.get('FAIL') == 'push': sys.exit(8)
    elif args[:1] == ['commit'] and os.environ.get('FAIL') == 'commit': sys.exit(9)
elif name == 'xcodebuild':
    if os.environ.get('FAIL') == 'build': sys.exit(6)
    p = Path('build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/MacOS')
    p.mkdir(parents=True)
    (p / 'Chatterbox').write_text('fixture')
elif name == 'codesign' and os.environ.get('FAIL') == 'signature': sys.exit(7)
elif name == 'pgrep': sys.exit(1)
elif name == 'ps': print('/Applications/Chatterbox.app/Contents/MacOS/Chatterbox')
'''


class Delivery(unittest.TestCase):
    def run_delivery(self, entry='ship.sh', args=(), **env):
        with tempfile.TemporaryDirectory(prefix='chatterbox-install-test-') as tmp:
            root = Path(tmp)
            (root / 'scripts/lib').mkdir(parents=True)
            for name in ('ship.sh', 'install.sh', 'lib/mac-install.sh', 'lib/build-lock.sh'):
                shutil.copy2(ROOT / 'scripts' / name, root / 'scripts' / name)
            check = root / 'scripts/check-sources.sh'
            check.write_text('#!/bin/sh\nexit 0\n')
            check.chmod(0o755)
            commands = root / 'commands'
            commands.mkdir()
            for name in ('xcodebuild', 'git', 'codesign', 'osascript', 'pgrep', 'rm',
                         'ditto', 'ln', 'open', 'cmp', 'ps'):
                p = commands / name
                p.write_text(STUB)
                p.chmod(0o755)
            process_env = dict(os.environ, HOME=str(root / 'home'),
                               PATH=f'{commands}:/usr/bin:/bin:/usr/sbin:/sbin',
                               CHATTERBOX_BUILD_LOCK_DIR=str(root / 'slots'),
                               CHATTERBOX_PRESSURE_FILE=str(root / 'no-pressure'),
                               CHATTERBOX_DATA_DIR='must-not-reach-open',
                               CHATTERBOX_COMPILE_CACHE='1')
            process_env.update(env)
            result = subprocess.run(['/bin/bash', str(root / 'scripts' / entry), *args],
                                    cwd=root, env=process_env, capture_output=True, text=True)
            events = [json.loads(line) for line in (root / 'events.jsonl').read_text().splitlines()]
            self.assertFalse((root / 'build/DerivedData.building').exists(), result.stderr + repr(events))
            self.assertFalse(list((root / 'slots').glob('slot-*')))
            return result, events

    def test_ship_builds_once_before_push_and_copy(self):
        result, events = self.run_delivery(STAGED='1', args=('Fixture commit',))
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = [e for e in events if e[0] == 'xcodebuild']
        self.assertEqual(len(builds), 1)
        self.assertIn('COMPILATION_CACHE_ENABLE_CACHING=YES', builds[0][1])
        self.assertIn('-jobs', builds[0][1])
        names = [e[0] for e in events]
        push = next(i for i, e in enumerate(events) if e[0] == 'git' and e[1][0] == 'push')
        self.assertLess(names.index('xcodebuild'), push)
        self.assertLess(push, names.index('ditto'))
        self.assertTrue(all(e[2] for e in events if e[0] in ('xcodebuild', 'ditto', 'cmp', 'open')))
        self.assertTrue(events[push][2])
        self.assertEqual(next(e for e in events if e[0] == 'open')[3], None)

    def test_install_builds_once_and_preserves_arguments(self):
        result, events = self.run_delivery('install.sh', ('--fixture', 'two words'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(e[0] == 'xcodebuild' for e in events), 1)
        opened = next(e for e in events if e[0] == 'open')
        self.assertEqual(opened[1], ['/Applications/Chatterbox.app', '--args', '--fixture', 'two words'])
        self.assertIsNone(opened[3])
        # Only reading which commit is installed (for scripts/rollback.sh), never committing.
        self.assertFalse(any(e[0] == 'git' and 'rev-parse' not in e[1] for e in events))
        # The app being replaced is kept, zipped, before it's removed.
        names = [e[0] for e in events]
        keep = next(i for i, e in enumerate(events) if e[0] == 'ditto' and '-c' in e[1])
        self.assertLess(keep, next(i for i, e in enumerate(events) if e[0] == 'ditto' and '-c' not in e[1]))

    def test_failures_leave_installed_app_untouched(self):
        for failure in ('build', 'signature', 'push', 'commit'):
            with self.subTest(failure=failure):
                result, events = self.run_delivery(FAIL=failure, STAGED='1', args=('Fixture',))
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(e[0] in ('osascript', 'rm', 'ditto', 'open') for e in events))

    def test_ship_guards_do_not_build_or_install(self):
        for env in ({'DIRTY': '1'}, {'STAGED': '1'}, {'BRANCH': 'feature'}):
            with self.subTest(env=env):
                result, events = self.run_delivery(**env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(e[0] in ('xcodebuild', 'ditto', 'open') for e in events))


if __name__ == '__main__':
    unittest.main(verbosity=2)
