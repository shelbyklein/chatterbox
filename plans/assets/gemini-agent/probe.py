import json, subprocess, sys, threading, time, os, queue
proc = subprocess.Popen([os.path.expanduser("~/.local/bin/agy"), "acp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1, cwd="/tmp/agy-probe/work")
log = open("/tmp/agy-probe/acp-probe.log", "w")
q = queue.Queue()
def reader():
    for line in proc.stdout:
        log.write("<< " + line); log.flush(); q.put(json.loads(line))
threading.Thread(target=reader, daemon=True).start()
def errreader():
    for line in proc.stderr: log.write("!! " + line); log.flush()
threading.Thread(target=errreader, daemon=True).start()
nid = [0]
def send(obj):
    s = json.dumps(obj); log.write(">> " + s + "\n"); log.flush(); proc.stdin.write(s + "\n"); proc.stdin.flush()
def request(method, params, auto_perm="allow", timeout=240):
    nid[0] += 1; rid = nid[0]
    send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
    end = time.time() + timeout
    while time.time() < end:
        try: m = q.get(timeout=1)
        except queue.Empty: continue
        if m.get("id") == rid and "method" not in m: return m
        if m.get("method") == "session/request_permission":
            opts = m["params"]["options"]
            pick = next((o for o in opts if o["kind"].startswith(auto_perm)), opts[0])
            send({"jsonrpc": "2.0", "id": m["id"], "result": {"outcome": {"outcome": "selected", "optionId": pick["optionId"]}}})
        elif "method" in m and "id" in m:
            send({"jsonrpc": "2.0", "id": m["id"], "error": {"code": -32601, "message": "unsupported"}})
    return {"timeout": method}
init = request("initialize", {"protocolVersion": 1, "clientCapabilities": {"fs": {"readTextFile": False, "writeTextFile": False}, "terminal": False}, "clientInfo": {"name": "probe", "version": "0"}})
print("INIT", json.dumps(init)[:1500])
new = request("session/new", {"cwd": "/tmp/agy-probe/work", "mcpServers": []})
print("NEW", json.dumps(new)[:2500])
sid = new.get("result", {}).get("sessionId")
r = request("session/prompt", {"sessionId": sid, "prompt": [{"type": "text", "text": "Create a file named hello.txt containing exactly: hi from gemini. Then reply with one short sentence."}]})
print("PROMPT1", json.dumps(r)[:500])
print("FILE", open("/tmp/agy-probe/work/hello.txt").read() if os.path.exists("/tmp/agy-probe/work/hello.txt") else None)
proc.stdin.close(); time.sleep(1); proc.kill()
