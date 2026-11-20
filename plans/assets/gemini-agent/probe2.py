import json, subprocess, sys, threading, time, os, queue
proc = subprocess.Popen([os.path.expanduser("~/.local/bin/agy"), "acp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1, cwd="/tmp/agy-probe/work")
log = open("/tmp/agy-probe/acp-probe2.log", "w")
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

import base64
init = request("initialize", {"protocolVersion": 1, "clientCapabilities": {"fs": {"readTextFile": False, "writeTextFile": False}, "terminal": False}, "clientInfo": {"name": "probe", "version": "0"}})
old = [json.loads(l[3:]) for l in open("/tmp/agy-probe/acp-probe.log") if l.startswith("<< ") and '"sessionId"' in l and '"models"' in l][0]["result"]["sessionId"]
t=time.time(); ld = request("session/load", {"sessionId": old, "cwd": "/tmp/agy-probe/work", "mcpServers": []})
print("LOAD", round(time.time()-t,1), json.dumps(ld)[:300])
print("SETCFG model", json.dumps(request("session/set_config_option", {"sessionId": old, "configId": "model", "value": "gemini-3.8-flash"}))[:300])
print("SETCFG effort", json.dumps(request("session/set_config_option", {"sessionId": old, "configId": "thought_level", "value": "low"}))[:200])
print("SETMODE", json.dumps(request("session/set_mode", {"sessionId": old, "modeId": "accept-edits"}))[:200])
r = request("session/prompt", {"sessionId": old, "prompt": [{"type": "text", "text": "What file did you create earlier, and what does it contain? One sentence."}]})
print("PROMPT2", json.dumps(r)[:300])
png = base64.b64encode(open("/Users/shelbyklein/Vibes/Chatterbox/plans/assets/gemini-agent/current-settings-picker.png","rb").read()).decode()
r = request("session/prompt", {"sessionId": old, "prompt": [{"type": "text", "text": "In five words or fewer, what is the heading at the top of this screenshot's model card?"}, {"type":"image","mimeType":"image/png","data":png}]})
print("IMAGE", json.dumps(r)[:200])
nid[0]+=1; rid=nid[0]
send({"jsonrpc":"2.0","id":rid,"method":"session/prompt","params":{"sessionId":old,"prompt":[{"type":"text","text":"Count slowly from 1 to 200, one number per line."}]}})
time.sleep(6); send({"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":old}})
end=time.time()+60; res=None
while time.time()<end:
    try: m=q.get(timeout=1)
    except queue.Empty: continue
    if m.get("id")==rid: res=m; break
print("CANCEL", json.dumps(res)[:300])
proc.stdin.close(); time.sleep(1); proc.kill()
