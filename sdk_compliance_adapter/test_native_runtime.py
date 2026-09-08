"""Run against the built Flutter app, never a mocked MethodChannel or SDK."""
import gzip
from http.server import BaseHTTPRequestHandler, HTTPServer, ThreadingHTTPServer
import http.client
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest

from macos_controller import NativeRuntime, controller


class NativeRuntimeTest(unittest.TestCase):
    def test_reset_isolates_pending_events_and_native_capture_retries(self):
        binary = os.environ['FLUTTER_COMPLIANCE_BINARY']
        batches = []
        batch_statuses = []
        flags_statuses = []
        flags_requests = []

        class Mock(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(404)
                self.end_headers()

            def do_POST(self):
                if self.headers.get('Transfer-Encoding') == 'chunked':
                    chunks = []
                    while True:
                        length = int(self.rfile.readline().split(b';')[0], 16)
                        if not length:
                            self.rfile.readline()
                            break
                        chunks.append(self.rfile.read(length))
                        self.rfile.read(2)
                    data = b''.join(chunks)
                else:
                    data = self.rfile.read(int(self.headers['Content-Length']))
                if self.headers.get('Content-Encoding') == 'gzip':
                    data = gzip.decompress(data)
                body = json.loads(data)
                if self.path.startswith('/batch'):
                    batches.append(body['batch'])
                    status = 503 if len(batches) == 1 else 200
                    batch_statuses.append(status)
                else:
                    status = flags_statuses.pop(0) if flags_statuses else 200
                    flags_requests.append(status)
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"featureFlags":{"native-flag":"variant-a"},"featureFlagPayloads":{}}')

        with tempfile.TemporaryDirectory(dir=os.environ['TEST_OUTPUT']) as output:
            runtime = NativeRuntime(binary, output, port=18313, proxy_port=19313)
            mock = ThreadingHTTPServer(('127.0.0.1', 19312), Mock)
            control = HTTPServer(('127.0.0.1', 18312), controller(runtime))
            threads = [threading.Thread(target=s.serve_forever) for s in (mock, control)]
            for thread in threads:
                thread.start()
            try:
                def post(path, payload=None):
                    client = http.client.HTTPConnection('127.0.0.1', 18312, timeout=45)
                    try:
                        client.request('POST', path, json.dumps(payload or {}),
                                       {'Content-Type': 'application/json'})
                        response = client.getresponse()
                        result = json.loads(response.read())
                        self.assertEqual(response.status, 200, result)
                        return result
                    finally:
                        client.close()

                config = {'api_key': 'phc_native_mock', 'host': 'http://127.0.0.1:19312',
                          'flush_at': 100, 'flush_interval_ms': 60000}
                post('/init', config)
                old_home, old_process = runtime.home, runtime.process
                post('/capture', {'distinct_id': 'native-user', 'event': 'stale-event'})
                self.assertEqual(batches, [])
                post('/reset')
                self.assertIsNotNone(old_process.poll())
                self.assertFalse(old_home.exists())
                self.assertIsNone(runtime.process)
                post('/init', dict(config, flush_interval_ms=1000))
                self.assertNotEqual(runtime.home, old_home)
                self.assertEqual(runtime.process.args, [str(Path(binary).resolve())])
                post('/capture', {'distinct_id': 'native-user', 'event': 'fresh-event',
                                  'properties': {'custom': 'preserved'}})
                post('/flush')
                self.assertEqual(batch_statuses, [503, 200])
                self.assertFalse(any(e['event'] == 'stale-event' for b in batches for e in b))
                events = [next(e for e in b if e['event'] == 'fresh-event') for b in batches]
                self.assertEqual(events[0]['uuid'], events[1]['uuid'])
                self.assertEqual(events[0]['timestamp'], events[1]['timestamp'])
                self.assertEqual(events[0]['distinct_id'], 'native-user')
                self.assertEqual(events[0]['properties']['custom'], 'preserved')
                self.assertEqual(events[0]['properties']['$lib'], 'posthog-flutter')
                for status in (502, 504):
                    before = len(flags_requests)
                    flags_statuses.extend([status, 200])
                    value = post('/get_feature_flag', {'distinct_id': 'native-user', 'key': 'native-flag'})
                    self.assertEqual(value['value'], 'variant-a')
                    self.assertEqual(flags_requests[before:], [status, 200])
                post('/capture', {'distinct_id': 'native-user', 'event': 'after-flags'})
                post('/flush')
                called = [e for b in batches[2:] for e in b if e['event'] == '$feature_flag_called']
                self.assertTrue(called)
                self.assertEqual(called[0]['properties']['$feature_flag_response'], 'variant-a')
                post('/reset')
            finally:
                control.shutdown()
                mock.shutdown()
                runtime.stop()
                control.server_close()
                mock.server_close()
                for thread in threads:
                    thread.join()


if __name__ == '__main__':
    unittest.main()
