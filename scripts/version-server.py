#!/usr/bin/env python3
"""
Version endpoint server - exposes current running container versions
Runs on port 8081, provides /version endpoint for GitHub workflow polling
"""

import json
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

PORT = 8081
STATE_FILE = "/var/run/image-poller-state.json"


def get_container_info(container_name):
    """Get running container's image digest and details"""
    try:
        result = subprocess.run(
            ["podman", "inspect", container_name],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)
        if data:
            return {
                "digest": data[0].get("ImageDigest", ""),
                "image": data[0].get("ImageName", ""),
                "created": data[0].get("Created", ""),
                "status": data[0].get("State", {}).get("Status", ""),
            }
    except (subprocess.CalledProcessError, json.JSONDecodeError, IndexError):
        return None


def get_poller_state():
    """Read poller state file for last update timestamps"""
    try:
        with open(STATE_FILE, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


class VersionHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/version":
            self.handle_version()
        elif self.path == "/health":
            self.handle_health()
        else:
            self.send_error(404, "Not Found")

    def handle_version(self):
        """Return version information for all managed containers"""
        # TODO: Read container list from config
        containers = ["buckman-proxy"]

        versions = {}
        for container in containers:
            info = get_container_info(container)
            if info:
                versions[container] = info

        # Add poller state
        poller_state = get_poller_state()

        response = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "containers": versions,
            "poller_state": poller_state,
        }

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(response, indent=2).encode())

    def handle_health(self):
        """Health check endpoint for ALB"""
        # Check if at least one container is running
        containers = ["buckman-proxy"]
        healthy = any(
            get_container_info(c) and get_container_info(c).get("status") == "running"
            for c in containers
        )

        if healthy:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy"}).encode())
        else:
            self.send_error(503, "No containers running")

    def log_message(self, format, *args):
        """Override to use systemd logging"""
        # Messages go to systemd journal
        print(f"{self.address_string()} - {format % args}")


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), VersionHandler)
    print(f"Starting version server on port {PORT}")
    server.serve_forever()
