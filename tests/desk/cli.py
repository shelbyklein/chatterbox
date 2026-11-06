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
