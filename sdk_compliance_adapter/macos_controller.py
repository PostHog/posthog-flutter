#!/usr/bin/env python3
"""HTTP control plane; every init runs the shipped Flutter app in a fresh home."""
import argparse
import http.client
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


class NativeRuntime:
    def __init__(self, binary, output, port=18311, proxy_port=19311):
        self.binary = str(Path(binary).resolve())
        self.output = Path(output).resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.port = port
        self.proxy_port = proxy_port
        self.process = None
        self.home = None
        self.log = None
        self.launch_count = 0

    def start(self):
        self.stop()
        self.launch_count += 1
        self.home = Path(tempfile.mkdtemp(prefix='flutter-home-', dir=self.output))
        tmp = self.home / 'tmp'
        tmp.mkdir()
        env = dict(os.environ, HOME=str(self.home), CFFIXED_USER_HOME=str(self.home),
                   TMPDIR=str(tmp) + '/', PORT=str(self.port), PROXY_PORT=str(self.proxy_port))
        self.log = (self.output / f'native-{self.launch_count}.log').open('wb')
        try:
            self.process = subprocess.Popen([self.binary], env=env, stdout=self.log,
                                            stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if self.process.poll() is not None:
                    raise RuntimeError(f'Flutter app exited: {self.process.returncode}')
                try:
                    status, _, _ = self.request('GET', '/health')
                    if status == 200:
                        return
                except OSError:
                    pass
                time.sleep(0.1)
            raise TimeoutError('Flutter app did not become ready within 30s')
        except BaseException:
            self.stop()
            raise

    def stop(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
            self.process = None
        if self.log is not None:
            self.log.close()
            self.log = None
        if self.home is not None:
            # Delete only the entire environment allocated above, after exit.
            # No SDK-private storage paths or queue files are addressed.
            shutil.rmtree(self.home)
            self.home = None

    def request(self, method, path, body=b'', content_type='application/json'):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=45)
        try:
            connection.request(method, path, body=body, headers={'Content-Type': content_type})
            response = connection.getresponse()
            return response.status, response.getheader('Content-Type', 'application/json'), response.read()
        finally:
            connection.close()


def controller(runtime):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.route()

        def do_POST(self):
            self.route()

        def route(self):
            try:
                path = self.path.split('?', 1)[0]
                if self.command == 'POST' and path == '/reset':
                    runtime.stop()
                    status, content_type, response = 200, 'application/json', b'{"success":true}'
                else:
                    if self.command == 'POST' and path == '/init':
                        runtime.start()
                    elif self.command == 'GET' and path == '/health' and runtime.process is None:
                        runtime.start()
                    if runtime.process is None:
                        raise RuntimeError('SDK not initialized')
                    body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
                    status, content_type, response = runtime.request(
                        self.command, self.path, body, self.headers.get('Content-Type', 'application/json'))
            except Exception as error:
                status, content_type = 500, 'application/json'
                response = json.dumps({'success': False, 'error': str(error)}).encode()
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response)

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('binary')
    parser.add_argument('output')
    parser.add_argument('--port', type=int, default=18310)
    parser.add_argument('--app-port', type=int, default=18311)
    parser.add_argument('--proxy-port', type=int, default=19311)
    args = parser.parse_args()
    runtime = NativeRuntime(args.binary, args.output, args.app_port, args.proxy_port)
    server = HTTPServer(('127.0.0.1', args.port), controller(runtime))

    def terminate(_signal, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminate)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        runtime.stop()


if __name__ == '__main__':
    main()
