#!/usr/bin/env python3
"""
Admin API Server for Activity Monitoring

Provides REST API endpoints for the admin dashboard.
"""

import json
import os
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from http.server import HTTPServer, BaseHTTPRequestHandler

# Add lib directory to path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from activity import get_logger


class AdminAPIHandler(BaseHTTPRequestHandler):
    """HTTP request handler for admin API."""

    def log_message(self, format, *args):
        """Suppress default logging."""
        pass

    def send_json_response(self, data, status=200):
        """Send a JSON response."""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def send_error_response(self, message, status=400):
        """Send an error response."""
        self.send_json_response({"error": message}, status)

    def do_OPTIONS(self):
        """Handle CORS preflight requests."""
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        # Health check
        if path == "/healthz":
            self.send_json_response({"status": "ok"})
            return

        # Activities endpoint
        if path == "/api/admin/activities":
            try:
                logger = get_logger()

                # Parse query parameters
                user = query.get("user", [None])[0]
                activity_type = query.get("type", [None])[0]
                start_time = query.get("start", [None])[0]
                end_time = query.get("end", [None])[0]
                limit = int(query.get("limit", ["100"])[0])
                offset = int(query.get("offset", ["0"])[0])

                activities = logger.get_activities(
                    user=user,
                    activity_type=activity_type,
                    start_time=start_time,
                    end_time=end_time,
                    limit=limit,
                    offset=offset,
                )

                self.send_json_response(activities)
            except Exception as e:
                self.send_error_response(str(e), 500)
            return

        # Stats endpoint
        if path == "/api/admin/stats":
            try:
                logger = get_logger()
                days = int(query.get("days", ["7"])[0])
                stats = logger.get_activity_stats(days=days)
                self.send_json_response(stats)
            except Exception as e:
                self.send_error_response(str(e), 500)
            return

        # Static files (admin dashboard)
        admin_dir = Path(__file__).parent
        if path == "/admin" or path == "/admin/":
            path = "/admin/index.html"

        if path.startswith("/admin/"):
            file_path = admin_dir / path[7:]  # Remove '/admin/' prefix
            if file_path.exists() and file_path.is_file():
                self.send_response(200)
                if file_path.suffix == ".html":
                    self.send_header("Content-Type", "text/html")
                elif file_path.suffix == ".js":
                    self.send_header("Content-Type", "application/javascript")
                elif file_path.suffix == ".css":
                    self.send_header("Content-Type", "text/css")
                else:
                    self.send_header("Content-Type", "application/octet-stream")
                self.end_headers()
                with open(file_path, "rb") as f:
                    self.wfile.write(f.read())
                return

        self.send_error_response("Not found", 404)


def run_server(port=8888):
    """Run the admin API server."""
    server = HTTPServer(("0.0.0.0", port), AdminAPIHandler)
    print(f"Admin API server running on port {port}")
    print(f"Dashboard available at http://localhost:{port}/admin")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == "__main__":
    port = int(os.environ.get("ADMIN_API_PORT", "8888"))
    run_server(port)
