"""Check source-link CLI forwarding without connecting to a real service."""
import contextlib
import io
from pathlib import Path
import runpy
import sys

namespace = runpy.run_path(str(Path(__file__).resolve().parents[2] / "bin" / "desk"))
calls = []


class Service:
    def request(self, operation, body):
        calls.append((operation, body))
        return {"incoming": [], "ready": [{"origin": {"kind": "email", "id": "original"}}]}


main = namespace["main"]
main.__globals__["Service"] = Service
url = "https://outlook.office.com/mail/deeplink/read/test-message"
with contextlib.redirect_stdout(io.StringIO()):
    sys.argv = ["desk", "add", "Review email", "--source", "email:test-message",
                "--source-title", "Original subject", "--source-url", url]
    main()
    sys.argv = ["desk", "source", "email:test-message", "--status", "checked",
                "--url", url, "--task", "B700FBB6-DB17-4C64-BB31-B5770D9B6FFB"]
    main()
assert calls[0] == ("desk", {"action": "add", "text": "Review email",
                           "origin": "email:test-message", "originTitle": "Original subject",
                           "originURL": url}), calls[0]
assert calls[1] == ("desk", {"action": "origin", "ref": "email:test-message",
                           "status": "checked", "url": url,
                           "task": "B700FBB6-DB17-4C64-BB31-B5770D9B6FFB"}), calls[1]
print("PASS: CLI preserves source URL/title and targets a single existing Desk task")

with contextlib.redirect_stdout(io.StringIO()) as output:
    sys.argv = ["desk", "list", "--json"]
    main()
import json
assert json.loads(output.getvalue())["ready"][0]["origin"]["id"] == "original"
assert calls[-1] == ("desk", {"action": "get"})
print("PASS: JSON listing retains sources in all board columns for de-duplication")

class ReusedService:
    def request(self, operation, body):
        return {"addition": {"id": "existing-task", "created": False}}
main.__globals__["Service"] = ReusedService
with contextlib.redirect_stdout(io.StringIO()) as output:
    sys.argv = ["desk", "add", "Changed wording", "--source", "email:original"]
    main()
assert "Already on the Desk (task existing-task)" in output.getvalue()
assert "On the Desk, with no place" not in output.getvalue()
print("PASS: CLI reports reused tasks without claiming a new task was created")

class InventoryService:
    def request(self, operation, body):
        return {"incoming": [], "tasks": [{"id": "old-review", "text": "Review this", "chatID": "thread",
                                          "origin": {"kind": "email", "id": "original"}}]}
main.__globals__["Service"] = InventoryService
with contextlib.redirect_stdout(io.StringIO()) as output:
    sys.argv = ["desk", "list"]
    main()
assert "Review this" in output.getvalue() and "email:original" in output.getvalue()
assert "old-review" in output.getvalue() and "linked to thread" in output.getvalue()
print("PASS: plain CLI list includes linked tasks and source references")
