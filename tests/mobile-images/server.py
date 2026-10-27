"""Isolated authenticated companion fixture; never contacts the real Mac service."""
import http.server
import json
import os
import struct
import threading
import time
import uuid
import zlib
from pathlib import Path

CHAT = '33333333-3333-3333-3333-333333333333'
IMAGE = '22222222-2222-2222-2222-222222222222'
OLDER = '11111111-1111-1111-1111-111111111111'
ROOT = Path(os.environ['CHATTERBOX_TEST_OUTPUT'])
mode = 'transient'
revision = 1
counts = {}
recovered = False
gate = threading.Event()

def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))

# A real, opaque blue/teal PNG, with stable 2:1 dimensions matching the placeholder.
rows = b''.join(b'\0' + bytes((25, 135, 190) if y < 80 else (35, 175, 155)) * 320 for y in range(160))
PNG = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', 320, 160, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')

def summary():
    return dict(id=CHAT, title='Image retries', project='Image retries', backend='claude',
                isRunning=False, isWaitingOnYou=False, updatedAt='2026-10-21T00:00:00Z')

def item(key, text, image=None):
    files = [] if image is None else [dict(id=image, name='Retry proof.png', mediaType='image/png',
                                         isImage=True, revision=str(revision))]
    return dict(id=str(uuid.uuid5(uuid.NAMESPACE_URL, key)), kind='image' if image else 'assistant',
                text=text, isStreaming=False, isCommentary=False, isPending=False, attachments=files, isQueued=False)

def detail():
    items = [item('older', 'An older image stays offscreen.', OLDER)]
    items += [item(str(n), f'Earlier reply {n}. ' + 'Read older messages here. ' * 18) for n in range(15)]
    items += [item('latest', 'Visible image retry proof.', IMAGE)]
    return dict(revision=revision, summary=summary(), settings='Claude', items=items, earlierCount=0)

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, value, status=200):
        self.binary(json.dumps(value).encode(), 'application/json', status)

    def binary(self, data, content_type, status=200):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        global mode, revision, counts, recovered, gate
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
        if self.path == '/v1/pair':
            return self.reply(dict(token='fixture', macName='Image Regression Mac', addresses=['127.0.0.1']))
        if self.path == '/test/reset':
            gate.set()
            gate = threading.Event()
            mode = body.get('mode', 'transient')
            revision += 1
            counts = {}
            recovered = False
            return self.reply({})
        if self.path == '/test/recover':
            recovered = True
            return self.reply({})
        if self.path == '/test/release':
            gate.set()
            return self.reply({})
        self.send_error(404)

    def do_GET(self):
        if self.path == '/test/counts':
            return self.reply(counts)
        if '/files/' in self.path:
            file = self.path.split('/files/')[1].split('?')[0].lower()
            counts[file] = counts.get(file, 0) + 1
            attempt = counts[file]
            (ROOT / 'requests.json').write_text(json.dumps(counts))
            if file == IMAGE:
                if mode == 'slow' and attempt == 1:
                    gate.wait(timeout=20)
                elif not recovered and (mode in ('permanent', 'manual') or attempt == 1):
                    return self.reply(dict(error='Fixture transient failure'), 503)
            return self.binary(PNG, 'image/png')
        if self.path == '/v1/chats':
            return self.reply(dict(revision=revision, groups=[dict(id='projects', kind='projects', title='Projects', chats=[summary()])]))
        if self.path == '/v1/addresses':
            return self.reply(dict(addresses=['127.0.0.1']))
        if self.path.startswith('/v1/chats/' + CHAT):
            return self.reply(dict(unchanged=True, revision=revision) if f'?since={revision}' in self.path else detail())
        self.send_error(404)

http.server.ThreadingHTTPServer(('127.0.0.1', 47410), Handler).serve_forever()
