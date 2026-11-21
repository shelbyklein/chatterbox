#!/usr/bin/python3
# A stand-in for `agy acp` (Antigravity CLI over the Agent Client Protocol), shaped like the
# real one's traffic in plans/assets/gemini-agent/acp-probe*.log. Logs every request it gets.
import json, os, sys, threading, queue
root = os.environ['CHATTERBOX_DATA_DIR']
if sys.argv[1:2] != ['acp']:
    # `agy -p /usage --output-format json` (GeminiUsage): one reply, no session.
    print(json.dumps({'status': 'SUCCESS', 'command': {'name': 'usage', 'data': {'groups': [{'name': 'Gemini Models', 'buckets': [
        {'id': 'gemini-5h', 'window': '5h', 'remaining_fraction': 0.75, 'reset_time': '2026-11-21T19:26:53Z'}]}]}}}))
    sys.exit(0)
log = open(root + '/agy-requests.jsonl', 'a')
with open(root + '/agy-launches.jsonl', 'a') as f: f.write(json.dumps({'args': sys.argv[1:], 'cwd': os.getcwd()}) + '\n')
out_lock = threading.Lock()
def send(obj):
    with out_lock:
        sys.stdout.write(json.dumps(obj) + '\n'); sys.stdout.flush()
answers = {}
answer_ready = threading.Condition()
cancelled = set()
counter = [0]
def update(sid, u): send({'jsonrpc': '2.0', 'method': 'session/update', 'params': {'sessionId': sid, 'update': u}})
def ask(sid, call):
    counter[0] += 1; rid = 1000 + counter[0]
    send({'jsonrpc': '2.0', 'id': rid, 'method': 'session/request_permission', 'params': {'sessionId': sid, 'toolCall': call,
          'options': [{'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'}, {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'}]}})
    with answer_ready:
        while rid not in answers: answer_ready.wait()
        return answers.pop(rid)
def elicit(sid):
    counter[0] += 1; rid = 2000 + counter[0]
    send({'jsonrpc': '2.0', 'id': rid, 'method': 'elicitation/create', 'params': {
        'sessionId': sid, 'mode': 'form', 'message': 'The agent has 2 questions.',
        'requestedSchema': {'type': 'object', 'properties': {
            'q1': {'type': 'string', 'title': 'Favorite color?', 'oneOf': [{'const': '1', 'title': 'Red'}, {'const': '2', 'title': 'Blue'}]},
            'q1_other': {'type': 'string', 'title': 'Other'},
            'q2': {'type': 'array', 'title': 'Toppings?', 'items': {'anyOf': [{'const': '1', 'title': 'Cheese'}, {'const': '2', 'title': 'Olives'}]}},
            'q2_other': {'type': 'string', 'title': 'Other'},
        }}
    }})
    with answer_ready:
        while rid not in answers: answer_ready.wait()
        return answers.pop(rid)
def config(model='gemini-4-neon'):
    return [{'id': 'model', 'currentValue': model, 'options': [{'value': 'gemini-4-neon', 'name': 'Gemini 4 Neon'}, {'value': 'gemini-3.8-flash', 'name': 'Gemini 3.8 Flash'}, {'value': 'claude-opus-5-5', 'name': 'Claude Opus 5.5'}]},
            {'id': 'thought_level', 'currentValue': 'high', 'options': [{'value': v, 'name': v} for v in ['low', 'medium', 'high', 'xhigh']]},
            {'id': 'mode', 'currentValue': 'default', 'options': []}]
def prompt(rid, p):
    sid = p['sessionId']
    # The message is the last text block (instructions and handoffs come before it).
    texts = [b.get('text', '') for b in p['prompt'] if b.get('type') == 'text']
    text = texts[-1].lower() if texts else ''
    update(sid, {'sessionUpdate': 'agent_thought_chunk', 'content': {'type': 'text', 'text': 'Thinking it over.'}})
    update(sid, {'sessionUpdate': 'usage_update', 'used': 12345, 'size': 1048576})
    if 'wedge' in text:
        # Like agy on 2026-11-20: the answer comes, then the turn never ends and cancels go unanswered.
        update(sid, {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'All done.'}})
        threading.Event().wait(3600); return
    if 'slow' in text:
        update(sid, {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'Counting: 1 2 3'}})
        while sid not in cancelled:
            threading.Event().wait(0.05)
        cancelled.discard(sid)
        send({'jsonrpc': '2.0', 'id': rid, 'result': {'stopReason': 'cancelled'}}); return
    if 'question' in text:
        result = elicit(sid)
        action = result.get('action', '')
        content = result.get('content', {})
        reply = 'Skipped questions.' if action != 'accept' else 'Answered: ' + json.dumps(content, sort_keys=True)
        update(sid, {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': reply}})
    elif 'edit' in text:
        path = os.path.join(os.getcwd(), 'hello.txt')
        call = {'sessionUpdate': 'tool_call', 'toolCallId': 'call-1', 'name': 'write_file', 'status': 'pending', 'kind': 'edit',
                'title': 'File ../../hello.txt', 'locations': [{'path': path}], 'rawInput': {'Path': path, 'Content': 'hi'},
                'content': [{'type': 'diff', 'path': path, 'newText': 'hi'}]}
        update(sid, dict(call, status='in_progress'))
        result = ask(sid, call)
        allowed = result.get('outcome', {}).get('optionId') == 'allow'
        if allowed:
            open(path, 'w').write('hi')
        update(sid, {'sessionUpdate': 'tool_call_update', 'toolCallId': 'call-1', 'status': 'completed' if allowed else 'failed',
                     'kind': 'edit', 'title': 'File hello.txt', 'locations': [{'path': path}]})
        update(sid, {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'Wrote hello.txt.' if allowed else 'Skipped the edit.'}})
    else:
        update(sid, {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'Hello from '}})
        update(sid, {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'Gemini.'}})
    send({'jsonrpc': '2.0', 'id': rid, 'result': {'stopReason': 'end_turn', 'usage': {'inputTokens': 10, 'outputTokens': 5}}})
for line in sys.stdin:
    m = json.loads(line)
    log.write(json.dumps(m) + '\n'); log.flush()
    method, rid, p = m.get('method'), m.get('id'), m.get('params', {})
    if method is None:
        with answer_ready:
            answers[rid] = m.get('result', {}); answer_ready.notify_all()
        continue
    if method == 'initialize':
        send({'jsonrpc': '2.0', 'id': rid, 'result': {'protocolVersion': 1, 'agentCapabilities': {'loadSession': True,
              'promptCapabilities': {'image': True}, 'sessionCapabilities': {'resume': {}, 'load': {}}}}})
    elif method == 'session/new':
        send({'jsonrpc': '2.0', 'id': rid, 'result': {'sessionId': 'fake-session-%d' % (len(open(root + '/agy-launches.jsonl').readlines())),
              'configOptions': config()}})
    elif method == 'session/resume':
        if p['sessionId'] == 'gone':
            send({'jsonrpc': '2.0', 'id': rid, 'error': {'code': -32602, 'message': 'no such session'}})
        else:
            send({'jsonrpc': '2.0', 'id': rid, 'result': {'configOptions': config()}})
    elif method == 'session/load':
        if p['sessionId'] == 'gone':
            send({'jsonrpc': '2.0', 'id': rid, 'error': {'code': -32602, 'message': 'no such session'}})
        else:
            update(p['sessionId'], {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'REPLAYED OLD TEXT'}})
            send({'jsonrpc': '2.0', 'id': rid, 'result': {'configOptions': config()}})
    elif method in ('session/set_config_option', 'session/set_mode'):
        send({'jsonrpc': '2.0', 'id': rid, 'result': {}})
    elif method == 'session/prompt':
        threading.Thread(target=prompt, args=(rid, p), daemon=True).start()
    elif method == 'session/cancel':
        cancelled.add(p['sessionId'])
    elif rid is not None:
        send({'jsonrpc': '2.0', 'id': rid, 'error': {'code': -32601, 'message': 'unknown'}})
