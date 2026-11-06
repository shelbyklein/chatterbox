#!/usr/bin/env python3
"""Move the existing seven-day morning routine to General; dry-run unless --apply.

Run against Dev first. Real data requires --allow-real after Ship. No review is run.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import tempfile
import uuid

TITLE = "ClickUp + Outlook morning priorities"
OLD_DELIVERY = "in this automation's On Target parent session"
NEW_DELIVERY = "in this automation's dedicated Morning priorities session"
REAL_DATA = Path.home() / "Library/Application Support/Chatterbox"
DEV_DATA = Path.home() / "Library/Application Support/Chatterbox Dev"


def plan(rows, source_folder):
    selected = [row for row in rows if row.get("title") == TITLE]
    if len(selected) != 7 or {row.get("weekday") for row in selected} != set(range(1, 8)):
        raise ValueError("Expected exactly seven weekdays of the named morning-priorities routine.")
    if len({row["id"] for row in selected}) != 7:
        raise ValueError("The routine has duplicate IDs.")
    if any((row.get("hour"), row.get("minute")) != (8, 30) for row in selected):
        raise ValueError("The routine's schedule no longer matches the reviewed 08:30 migration.")
    if len({row.get("instructions") for row in selected}) != 1:
        raise ValueError("The weekday instructions differ; reconcile them before migration.")
    if all(row.get("projectFolder") is None for row in selected):
        destinations = {row.get("reportSessionID") for row in selected}
        if len(destinations) != 1 or None in destinations:
            raise ValueError("The general routine has conflicting reporting sessions.")
        report_id = next(iter(destinations))
        uuid.UUID(report_id)
        if any(row.get("reportSessionTitle") != "Morning priorities" or OLD_DELIVERY in row["instructions"] for row in selected):
            raise ValueError("The general routine differs from the reviewed migration.")
        return rows, report_id, False
    if any(row.get("projectFolder") != source_folder or row.get("reportSessionID") is not None
           or row.get("reportSessionTitle") is not None for row in selected):
        raise ValueError("The routine's current target differs from On Target; no changes made.")
    if any(row["instructions"].count(OLD_DELIVERY) != 1 for row in selected):
        raise ValueError("The delivery sentence changed; review it before migration.")
    report_id = str(uuid.uuid4()).upper()
    result = json.loads(json.dumps(rows))
    ids = {row["id"] for row in selected}
    for row in result:
        if row.get("id") in ids:
            row.pop("projectFolder")
            row["reportSessionID"] = report_id
            row["reportSessionTitle"] = "Morning priorities"
            row["instructions"] = row["instructions"].replace(OLD_DELIVERY, NEW_DELIVERY)
    return result, report_id, True


class Service:
    def __init__(self, data):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(15)
        self.sock.connect(str(data / "daemon.sock"))
        self.file = self.sock.makefile("rwb")
        hello = self.request("hello", {"role": "agent"})
        if not hello.get("generalAutomations"):
            raise ValueError("This service does not support General automations; install the verified build first.")

    def request(self, operation, body):
        rid = str(uuid.uuid4())
        self.file.write((json.dumps({"version": 1, "id": rid, "operation": operation, "body": body}) + "\n").encode())
        self.file.flush()
        while True:
            line = self.file.readline()
            if not line:
                raise ValueError("The service disconnected.")
            reply = json.loads(line)
            if reply.get("id") == rid:
                if reply.get("error"):
                    raise ValueError(reply["error"])
                return reply.get("result")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", required=True, type=Path)
    parser.add_argument("--from-project", default=str(Path.home() / "Vibes/On Target"))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--allow-real", action="store_true")
    parser.add_argument("--offline", action="store_true", help="isolated fixtures only; no runtime session preparation")
    args = parser.parse_args()
    data = args.data_dir.expanduser().resolve()
    if args.apply and data == REAL_DATA.resolve() and not args.allow_real:
        parser.error("Real migration is a Ship step; --allow-real is required.")
    if args.offline and (data in (REAL_DATA.resolve(), DEV_DATA.resolve())
                         or not (str(data).startswith("/private/tmp/") or str(data).startswith("/tmp/")
                                 or "/build/" in str(data))):
        parser.error("--offline is limited to isolated temporary/build fixtures.")
    config = data / "Automations.json"
    original = config.read_bytes()
    rows = json.loads(original)
    migrated, report_id, changed = plan(rows, args.from_project)
    if not args.apply:
        print("Dry run: seven weekdays; " + ("move On Target → General" if changed else "already General; no change"))
        print("Preserves IDs, 08:30 schedule, enabled flags, agent settings, history, reports and Desk instructions.")
        return
    service = None if args.offline else Service(data)
    state = data / "automation-state.json"
    if changed:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        backup = data / "Backups" / ("general-automations-" + stamp)
        backup.mkdir(parents=True)
        shutil.copy2(config, backup / config.name)
        if state.exists():
            shutil.copy2(state, backup / state.name)
        report = data / "Conversations" / (report_id + ".json")
        if report.exists():
            raise ValueError("Reporting-session ID collision; no changes made.")
        encoded = (json.dumps(migrated, indent=2, ensure_ascii=False) + "\n").encode()
        fd, temporary = tempfile.mkstemp(prefix=".general-automations-", dir=data)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(encoded)
                handle.flush()
                os.fsync(handle.fileno())
            if hashlib.sha256(config.read_bytes()).digest() != hashlib.sha256(original).digest():
                raise ValueError("The configuration changed concurrently; retry after reviewing it.")
            os.replace(temporary, config)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        if json.loads(config.read_bytes()) != migrated:
            raise ValueError("Saved configuration differs; inspect the backup before continuing.")
        print("Moved seven weekdays to General. Backup: " + str(backup))
    else:
        print("Already General; configuration unchanged.")
    if service:
        selected = next(row for row in migrated if row.get("title") == TITLE)
        prepared = service.request("automationReportSession", {"id": selected["id"]})
        if prepared.get("threadID") != report_id:
            raise ValueError("The runtime returned a different reporting session.")
        print("Verified dedicated Morning priorities session; no agent or review started.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        raise SystemExit("Migration stopped: " + str(error))
