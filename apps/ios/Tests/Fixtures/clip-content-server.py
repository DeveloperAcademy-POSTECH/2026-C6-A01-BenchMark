#!/usr/bin/env python3
"""Local-only fixture API. Never deploy: it serves explicit sample files, no donor data."""
import argparse, hashlib, json, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=8765)
parser.add_argument('--model', type=Path, required=True)
parser.add_argument('--image', type=Path, required=True)
args = parser.parse_args()
model = args.model.read_bytes()
image = args.image.read_bytes()
base = f'http://127.0.0.1:{args.port}'

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/assets/model.usdz': return self.send(model, 'model/vnd.usdz+zip')
        if path == '/assets/story.png': return self.send(image, 'image/png')
        if path == '/assets/redirect.usdz':
            self.send_response(302); self.send_header('Location', 'https://untrusted.invalid/model.usdz'); self.end_headers(); return
        if path == '/v1/benches/oversize/story':
            self.send_response(200); self.send_header('Content-Length', '999999999'); self.end_headers(); return
        if path == '/v1/benches/slow/story':
            self.send_response(200); self.end_headers()
            try:
                for _ in range(200): self.wfile.write(b'x' * 1024); self.wfile.flush(); time.sleep(.05)
            except (BrokenPipeError, ConnectionResetError): pass
            return
        allowed = ['/v1/benches/demo-bench/story', '/v1/stories/demo-story', '/v1/benches/wrong/story', '/v1/benches/private/story']
        if path in allowed:
            story = dict(id='demo-story', benchID='demo-bench', published='private' not in path,
                title='테스트 벤치의 오래 남는 이야기', body='외부 API로 불러온 개발용 예시입니다. 실제 기부자 데이터가 아닙니다.',
                donorDisplayName='개발용 예시', images=[dict(url=base+'/assets/story.png')],
                character=dict(name='넙죽이', heightMeters=1.0, asset=dict(url=base+'/assets/model.usdz', sha256=hashlib.sha256(model).hexdigest())))
            return self.send(json.dumps(story, ensure_ascii=False).encode(), 'application/json; charset=utf-8')
        self.send_response(404); self.end_headers()

    def send(self, data, mime):
        self.send_response(200); self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *_): pass

print(f'Fixture API listening at {base}', flush=True)
ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
