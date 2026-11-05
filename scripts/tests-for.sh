#!/bin/bash
# Which test scripts cover the files you changed (AGENTS.md, "Targeted tests").
#
#   scripts/tests-for.sh [FILE…]   the tests for FILE…; with none, for what this checkout changed:
#                                  commits since origin/main, uncommitted and new files, Core's too
#   scripts/tests-for.sh --why …   the same, with the reason each test is listed, and the tests
#                                  that only compile a changed file
#   scripts/tests-for.sh --all     every test script (the full suite)
#   scripts/tests-for.sh --run …   run the listed tests one after another (logs in build/test-logs),
#                                  then print which passed and failed; e.g. `--run --all`
#
# Worked out from the test scripts themselves, so it stays right as they change. A test covers a
# changed file when
#   - the file is the test script or under the tests/<dir> it uses;
#   - the script names the file (scripts/lib/safe-stop.sh, ChatterboxMobile/MobileComposerDraft.swift);
#   - or the script compiles the file (its find -L folders, runtime-sources.sh, the source paths it
#     lists) and the test's own code uses a type the file declares (DeskStore, MacPressure), or,
#     for a file of extensions only, one of the functions it adds.
# scripts/test-map.txt adds what that can't see (a file a test uses through a built app, say).
# Paths in Core may be given as Core/… or as the checkout's own path (Chatterbox/Engine/…).
# scripts/check-sources.sh is listed when files were added or removed or project.yml changed.
cd "$(dirname "$0")/.." || exit 1
exec /usr/bin/python3 -I - "$@" <<'PY'
import os, re, subprocess, sys
from pathlib import Path

ROOT = Path.cwd()
args = sys.argv[1:]
why = '--why' in args
run = '--run' in args
everything = '--all' in args
files = [a for a in args if not a.startswith('--')]
tests = sorted(p for p in (ROOT / 'scripts').glob('test-*.sh'))

def git(*a, cwd=ROOT):
    r = subprocess.run(['git', *a], cwd=cwd, capture_output=True, text=True)
    return r.stdout.splitlines() if r.returncode == 0 else []

def changed_files():
    """Commits since origin/main, uncommitted and new files; Core's too (as Core/…). Also
    whether files were added or removed."""
    out, structural = set(), False
    for cwd, prefix in ((ROOT, ''), (ROOT / 'Core', 'Core/')):
        if not (cwd / '.git').exists():
            continue
        base = git('merge-base', 'HEAD', 'origin/main', cwd=cwd)
        if base:
            for line in git('diff', '--name-status', base[0], cwd=cwd):
                status, *paths = line.split('\t')
                out.update(prefix + p for p in paths)
                structural |= status[0] in 'ADR'
        for line in git('status', '--porcelain', '--untracked-files=all', cwd=cwd):
            status, path = line[:2], line[3:].split(' -> ')[-1]
            out.add(prefix + path)
            structural |= '?' in status or 'A' in status or 'D' in status or 'R' in status
    out.discard('Core')
    return sorted(out), structural

def normalize(path):
    """A repo-relative path, Core/X written as the checkout's X when that's where it shows."""
    p = Path(path)
    if p.is_absolute():
        try: p = p.relative_to(ROOT)
        except ValueError: return str(p)
    s = str(p)
    if s.startswith('Core/') and (ROOT / s[5:]).exists():
        return s[5:]
    return s

# --- What each test script uses ------------------------------------------------------------

COMMON = {'scripts/lib/test-hygiene.sh', 'scripts/lib/source-list.sh'}   # every test sources these
TOP = ['Chatterbox', 'ChatterboxRuntime', 'ChatterboxDaemon', 'ChatterboxHost', 'ChatterboxMobile',
       'ChatterboxWidget', 'Shared', 'Core', 'bin', 'scripts', 'tests', 'prompts']
PATH_RE = re.compile(r"(?<![\w.-])((?:%s)(?:/[\w.+@-]+)+)" % '|'.join(TOP))
BARE_DIR_RE = re.compile(r"""['"](%s)['"/]""" % '|'.join(TOP[:7]))
FIND_RE = re.compile(r"find -L ((?:[\w/.-]+ )+)-")

def files_under(rel):
    p = ROOT / rel
    if p.is_file():
        return {rel}
    if p.is_dir():
        return {str(f.relative_to(ROOT)) for f in p.rglob('*') if f.is_file() or (f.is_symlink() and not f.is_dir())}
    return set()

def swift_under(rel):
    p = ROOT / rel
    if p.is_file():
        return {rel}
    found = set()
    if p.is_dir():
        for dirpath, _, names in os.walk(p, followlinks=True):
            for n in names:
                if n.endswith('.swift'):
                    found.add(str(Path(dirpath, n).relative_to(ROOT)))
    return found

_runtime = None
def runtime_sources():
    global _runtime
    if _runtime is None:
        r = subprocess.run(['./scripts/runtime-sources.sh'], cwd=ROOT, capture_output=True, text=True)
        _runtime = set(r.stdout.split())
    return _runtime

class Test:
    def __init__(self, path):
        self.path = path
        self.name = str(path.relative_to(ROOT))
        text = path.read_text(errors='replace')
        lines = [l for l in text.splitlines() if not any(c in l for c in ('lib/test-hygiene.sh', 'lib/source-list.sh'))]
        if self.name == 'scripts/test-tests-for.sh':
            lines = []      # the paths it names are examples, not files it uses
        body = '\n'.join(lines)
        self.named = set()      # files the script names (directly used)
        self.own = set()        # its tests/<dir> files and itself
        self.compiles = set()   # Swift it compiles
        self.own.add(self.name)
        for m in PATH_RE.finditer(body):
            rel = normalize(m.group(1).rstrip('.'))
            if rel.startswith('tests/'):
                parts = rel.split('/')
                self.own |= files_under('/'.join(parts[:2]))
            elif (ROOT / rel).is_dir():
                self.compiles |= swift_under(rel)
            elif rel.endswith('.swift') and (ROOT / rel).exists():
                self.compiles.add(rel)          # a source it compiles: covered if the test uses it
            elif (ROOT / rel).exists():
                self.named.add(rel)
        for m in BARE_DIR_RE.finditer(body):
            self.compiles |= swift_under(normalize(m.group(1)))
        for m in FIND_RE.finditer(body):
            for d in m.group(1).split():
                self.compiles |= swift_under(normalize(d))
        if 'runtime-sources.sh' in body:
            self.compiles |= runtime_sources()
        self.named -= COMMON
        own_text = []
        for f in self.own:
            if f.endswith(('.swift', '.py', '.sh', '.mjs', '.js')) and (ROOT / f).is_file():
                own_text.append((ROOT / f).read_text(errors='replace'))
        own_text.append(body)
        self.words = set(re.findall(r'[A-Za-z_]\w+', '\n'.join(own_text)))

DECL_RE = re.compile(r'^(?:(?:@\w+(?:\([^)]*\))?|public|private|fileprivate|internal|open|final|nonisolated(?:\(unsafe\))?|indirect)\s+)*'
                     r'(class|struct|enum|protocol|actor|extension|typealias)\s+([A-Za-z_]\w*)', re.M)
MEMBER_RE = re.compile(r'^(?:    |\t)(?:(?:@\w+(?:\([^)]*\))?|public|private|fileprivate|internal|open|final|static|class|override|mutating|nonisolated)\s+)*'
                       r'(?:func|var|let)\s+([A-Za-z_]\w*)', re.M)

def declared(rel):
    """The names a test would use to reach this Swift file: its top-level types; for a file of
    extensions only, the camelCase functions and properties they add."""
    try:
        text = (ROOT / rel).read_text(errors='replace')
    except OSError:
        return set()
    types = {n for kind, n in DECL_RE.findall(text) if kind != 'extension'}
    if types:
        return types
    return {n for n in MEMBER_RE.findall(text) if re.search(r'[a-z][A-Z]', n)}

def manual_map():
    rules = []
    f = ROOT / 'scripts' / 'test-map.txt'
    if f.exists():
        for line in f.read_text().splitlines():
            line = line.split('#', 1)[0].split()
            if len(line) >= 2:
                rules.append((line[0], line[1:]))
    return rules

def matches(pattern, path):
    from fnmatch import fnmatch
    return fnmatch(path, pattern) or path.startswith(pattern.rstrip('/') + '/')

# --- Run ------------------------------------------------------------------------------------

def run_all(names):
    logs = ROOT / 'build' / 'test-logs'
    logs.mkdir(parents=True, exist_ok=True)
    results = []
    for n in names:
        log = logs / (Path(n).stem + '.log')
        print(f'--- {n}', flush=True)
        with log.open('w') as out:
            code = subprocess.run(['./' + n], cwd=ROOT, stdout=out, stderr=subprocess.STDOUT).returncode
        results.append((code, n, log))
        print(f'    {"pass" if code == 0 else f"FAIL ({code})"}  {log.relative_to(ROOT)}', flush=True)
    failed = [r for r in results if r[0]]
    print(f'\n{len(results) - len(failed)} passed, {len(failed)} failed')
    for code, n, log in failed:
        print(f'  FAIL {n} ({code}): {log.relative_to(ROOT)}')
    return 1 if failed else 0

if everything:
    names = [str(t.relative_to(ROOT)) for t in tests]
    if run:
        sys.exit(run_all(names))
    print('\n'.join(names))
    sys.exit(0)

structural = False
if not files:
    files, structural = changed_files()
    if not files:
        print('tests-for: nothing changed here (give files, or --all)', file=sys.stderr)
        sys.exit(0)
changed = sorted({normalize(f) for f in files})
if any(f in ('project.yml',) or f.endswith('.pbxproj') for f in changed):
    structural = True

suite = [Test(t) for t in tests]
rules = manual_map()
picked = {}     # test name -> reasons
compiled_only = {}
for f in changed:
    names = declared(f) if f.endswith('.swift') else set()
    stem = Path(f).name
    hit = False
    for t in suite:
        reason = None
        if f in t.own:
            reason = f'{f}: the test or its own files'
        elif f in t.named:
            reason = f'{f}: named in the script'
        elif f in t.compiles and names & t.words:
            reason = f'{f}: uses {", ".join(sorted(names & t.words)[:3])}'
        if reason:
            picked.setdefault(t.name, []).append(reason); hit = True
        elif f in t.compiles:
            compiled_only.setdefault(f, []).append(t.name)
    for pattern, targets in rules:
        if matches(pattern, f):
            for target in targets:
                target = target if '/' in target else 'scripts/' + target
                if (ROOT / target).exists():
                    picked.setdefault(target, []).append(f'{f}: scripts/test-map.txt ({pattern})'); hit = True
    if not hit and why:
        n = len(compiled_only.get(f, []))
        print(f'# {f}: no test uses it directly' + (f'; {n} compile it' if n else ''), file=sys.stderr)

if structural:
    picked.setdefault('scripts/check-sources.sh', []).append('files added or removed, or project.yml changed')

order = sorted(picked)
if run:
    sys.exit(run_all(order))
for name in order:
    print(name)
    if why:
        for r in picked[name]:
            print(f'    {r}')
if why and compiled_only:
    print('\nAlso compile a changed file (no direct use found):')
    for f, ts in sorted(compiled_only.items()):
        rest = [t for t in ts if t not in picked]
        if rest:
            print(f'  {f}: {len(rest)} — {", ".join(Path(t).stem.removeprefix("test-") for t in rest[:8])}{" …" if len(rest) > 8 else ""}')
PY
