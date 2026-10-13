#!/usr/bin/env python3
"""Mock HDHomeRun tuner + SiliconDust API for fetch-guide.sh integration tests.

Routes (GET only):
  /discover.json          -> minimal SiliconDust-style discovery document
  /api/xmltv?...          -> minimal valid XMLTV guide (plain, --compressed handles it);
                             403 unless DeviceAuth matches the discover.json token
  /bad/...                -> 200 with garbage (the script's own sanity check must catch it)
  /err/...                -> 500
  /ctrl/...               -> 200 with ANSI escapes / control bytes (not XMLTV)

Usage: python3 tests/mock_server.py [port] [host]   (defaults 8964, 127.0.0.1)
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlsplit

# The token has characters that must be URL-encoded (+ / =).
DEVICE_AUTH = "abc123+MOCK/AUTH=TOKEN0"
DISCOVER = json.dumps({"DeviceID": "DEADBEEF0123", "DeviceAuth": DEVICE_AUTH, "FriendlyName": "mock-tuner"})
XMLTV = """<tv generator-info-name="mock-server">
  <channel id="2.1"><display-name>MOCK 2.1</display-name></channel>
  <programme start="20261009000000 +0000" stop="20261009010000 +0000" channel="2.1">
    <title>Mock Show A</title>
  </programme>
  <programme start="20261009010000 +0000" stop="20261009020000 +0000" channel="2.1">
    <title>Mock Show B</title>
  </programme>
</tv>
"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        bad_xml = self.path.startswith("/bad")
        error = self.path.startswith("/err")
        ctrl = self.path.startswith("/ctrl")
        url = urlsplit(self.path)
        if url.path == "/api/xmltv" and parse_qs(url.query).get("DeviceAuth") != [DEVICE_AUTH]:
            body = b"bad DeviceAuth\n"
            self.send_response(403)
        elif error:
            body = b"internal server error\n"
            self.send_response(500)
        elif ctrl:
            body = b"\x1b[31mEVIL\x1b[0m\x07\x00\r not xmltv\n"
            self.send_response(200)
        elif bad_xml:
            body = b"<html><body>garbage, not xmltv</body></html>\n"
            self.send_response(200)
        elif self.path.split("?")[0] in ("/discover.json", "/api/xmltv"):
            body = (DISCOVER if self.path.startswith("/discover.json") else XMLTV).encode()
            self.send_response(200)
        else:
            self.send_response(404)
            body = b"not found\n"
        self.send_header("Content-Type", "application/xml")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8964
    host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    server = HTTPServer((host, port), Handler)
    sys.stderr.write(f"mock server ready on {host}:{port}\n")
    sys.stderr.flush()
    server.serve_forever()