"""Exercise the real built daemon with disposable secrets and an isolated store."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import uuid

root = Path(tempfile.mkdtemp(prefix="golem-secrets-wire.", dir="/tmp"))
data = root / "data"
data.mkdir()
binary = Path("build/runtime/secret-access-fixture").resolve()
binary.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2("build/DerivedData/Build/Products/Debug/Chatterbox.app/Contents/MacOS/chatterboxd", binary)
entry_id = str(uuid.uuid4()).upper()
value = "fixture-only-wire-secret-value"
entry = dict(id=entry_id, name="Fixture", variable="FIXTURE_ONLY", note="", username="", projects=[], created=0)
(data / "Secrets.json").write_text(json.dumps([entry]))
(data / ("test-secret-" + entry_id)).write_text(value)
env = dict(os.environ, CHATTERBOX_DATA_DIR=str(data), CHATTERBOX_HOST_DIR=str(root / "host"),
           CHATTERBOX_AGENT_PORT="0", CHATTERBOX_COMPANION_PORT="0",
           CHATTERBOX_PREFERENCES_SUITE="chatterbox.secrets.wire." + root.name,
           CHATTERBOX_TEST_DISABLE_COMPUTER="1")


class Client:
    def __init__(self, role):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(5)
        self.socket.connect(str(data / "daemon.sock"))
        self.stream = self.socket.makefile("rwb")
        self.hello = self.call("hello", {"role": role})

    def call(self, operation, body=None):
        request = dict(version=1, id=str(uuid.uuid4()), operation=operation, body=body or {})
        self.stream.write((json.dumps(request) + "\n").encode())
        self.stream.flush()
        reply = json.loads(self.stream.readline())
        assert value not in json.dumps(reply), "secret value escaped into RPC response"
        return reply

    def close(self):
        self.stream.close()
        self.socket.close()


def start(trusted_fixture):
    launch_env = dict(env)
    launch_env.pop("CHATTERBOX_TEST_TRUST_UI", None)
    if trusted_fixture:
        launch_env["CHATTERBOX_TEST_TRUST_UI"] = "1"
    process = subprocess.Popen([str(binary)], env=launch_env,
                               stdout=(root / ("trusted.log" if trusted_fixture else "untrusted.log")).open("wb"),
                               stderr=subprocess.STDOUT)
    for _ in range(200):
        assert process.poll() is None, "fixture service exited during startup"
        if (data / "daemon.sock").exists():
            return process
        time.sleep(0.05)
    stop(process)
    raise AssertionError("fixture service did not start")


def stop(process):
    # This is a dedicated, empty fixture with no provider children. Keep the same
    # shared process-tree guard used by production cleanup; never kill a live daemon.
    if process.poll() is None:
        subprocess.run(["bash", "-c", 'source scripts/lib/safe-stop.sh; safe_stop "$1"',
                        "secrets-test-cleanup", str(process.pid)], check=True)
        process.wait(timeout=5)


process = None
try:
    process = start(False)
    client = Client("ui")
    assert client.hello.get("error") == "permission_denied", "unsigned process obtained UI identity"
    client.close()
    stop(process)
    process = start(True)
    client = Client("ui")
    assert "result" in client.hello
    for role in ["agent", "golem", "golem-ui"]:
        unprivileged = Client(role)
        assert "result" in unprivileged.hello
        for operation in ["refreshSecrets", "authorizeSecret"]:
            reply = unprivileged.call(operation, {"secretID": entry_id})
            assert reply.get("error") == "permission_denied", (role, operation, reply)
        unprivileged.close()
    assert client.call("refreshSecrets")["result"] == {"availability": {entry_id: True}}
    assert client.call("authorizeSecret", {"secretID": entry_id})["result"] == {
        "availability": {entry_id: True}, "authorized": True}
    assert client.call("authorizeSecret", {"secretID": str(uuid.uuid4())}).get("error") == "secret_not_found"
    (data / ("test-secret-" + entry_id)).unlink()
    assert client.call("refreshSecrets")["result"] == {"availability": {entry_id: False}}
    assert client.call("authorizeSecret", {"secretID": entry_id})["result"] == {
        "availability": {entry_id: False}, "authorized": False}
    (data / "Secrets.json").write_text("[]")
    assert client.call("refreshSecrets")["result"] == {"availability": {}}
    client.close()
    stop(process)
    process = None
    persisted = (data / "runtime-state.json").read_text()
    assert value not in persisted and "authorizeSecret" not in persisted and "refreshSecrets" not in persisted
    print("PASS unsigned UI rejected; agents and Golem denied secret status and authorization")
    print("PASS service reload, targeted authorization, missing-value status and removal")
    print("PASS no secret values in RPC responses or persisted command receipts")
    print("Secret wire artifacts:", root)
finally:
    if process is not None:
        stop(process)
    binary.unlink(missing_ok=True)
