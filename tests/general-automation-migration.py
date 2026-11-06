import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/migrate-morning-priorities.py"
spec = importlib.util.spec_from_file_location("migration", SCRIPT)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.rows = [dict(id=str(uuid.uuid4()), title=migration.TITLE, weekday=day, hour=8, minute=30,
                         enabled=day != 1, backend="codex", createdAt="2026-11-02T16:35:47Z",
                         projectFolder="/project/On Target", instructions="Report " + migration.OLD_DELIVERY + ". Keep all source limits.")
                     for day in range(1, 8)]
        self.other = dict(title="WordPress updates", projectFolder="/project/site", enabled=True)
        self.rows.append(self.other)

    def test_exact_delta_and_idempotency(self):
        old = copy.deepcopy(self.rows)
        result, report_id, changed = migration.plan(self.rows, "/project/On Target")
        self.assertTrue(changed)
        self.assertEqual(self.rows, old)
        self.assertEqual(result[-1], self.other)
        for before, after in zip(old[:7], result[:7]):
            expected = dict(before)
            expected.pop("projectFolder")
            expected.update(reportSessionID=report_id, reportSessionTitle="Morning priorities",
                            instructions=before["instructions"].replace(migration.OLD_DELIVERY, migration.NEW_DELIVERY))
            self.assertEqual(after, expected)
        again, same_id, changed = migration.plan(result, "/project/On Target")
        self.assertFalse(changed)
        self.assertEqual((again, same_id), (result, report_id))

    def test_mismatch_is_refused(self):
        for edit in [lambda r: r.pop(0), lambda r: r[0].update(projectFolder="/other"),
                     lambda r: r[0].update(hour=9), lambda r: r[0].update(instructions="Different brief"),
                     lambda r: r[0].update(weekday=2)]:
            rows = copy.deepcopy(self.rows)
            edit(rows)
            with self.assertRaises(ValueError):
                migration.plan(rows, "/project/On Target")

    def test_files_backups_and_dry_run(self):
        with tempfile.TemporaryDirectory(prefix="general-migration-", dir="/tmp") as directory:
            root = Path(directory)
            config = root / "Automations.json"
            config.write_text(json.dumps(self.rows))
            state = root / "automation-state.json"
            state.write_text('{"existing-day":{"lastRun":"2026-11-06T13:30:00Z"}}')
            before, state_before = config.read_bytes(), state.read_bytes()
            command = ["python3", str(SCRIPT), "--data-dir", str(root), "--from-project", "/project/On Target", "--offline"]
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(config.read_bytes(), before)
            self.assertFalse((root / "Backups").exists())
            subprocess.run(command + ["--apply"], check=True, capture_output=True)
            self.assertEqual(state.read_bytes(), state_before)
            backups = list((root / "Backups").iterdir())
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / "Automations.json").read_bytes(), before)
            self.assertEqual((backups[0] / state.name).read_bytes(), state_before)
            applied = config.read_bytes()
            subprocess.run(command + ["--apply"], check=True, capture_output=True)
            self.assertEqual(config.read_bytes(), applied)
            self.assertEqual(len(list((root / "Backups").iterdir())), 1)
            self.assertFalse((root / "Conversations").exists())


unittest.main()
