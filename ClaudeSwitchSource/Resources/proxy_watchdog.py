#!/usr/bin/env python3
"""
Claude Proxy Watchdog (MCP Integration)
Ensures the local loopback proxy is always running and healthy whenever Claude Desktop is open.
"""

import sys
import os
import json
import time
import threading
import urllib.request
import urllib.error
import subprocess

PROXY_PORT = 8080
HEALTH_URL = f"http://127.0.0.1:{PROXY_PORT}/api/hello"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DAEMON_PATH = os.path.join(SCRIPT_DIR, "proxy_daemon.py")

def log(msg):
    try:
        with open("/tmp/claude_watchdog.log", "a", encoding="utf-8") as f:
            f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except Exception:
        pass

def is_proxy_healthy():
    try:
        req = urllib.request.Request(HEALTH_URL, method="GET")
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            return resp.status == 200
    except Exception:
        return False

def ensure_proxy_running():
    if is_proxy_healthy():
        return True

    log("Proxy not responding. Initiating launch...")

    # 1. Try kicking launchd service if registered
    uid = os.getuid()
    try:
        res = subprocess.run(
            ["/bin/launchctl", "kickstart", "-k", f"gui/{uid}/com.anthropic.claude.proxy"],
            capture_output=True,
            timeout=3
        )
        if res.returncode == 0:
            time.sleep(0.5)
            if is_proxy_healthy():
                log("Successfully started proxy via launchd kickstart")
                return True
    except Exception as e:
        log(f"launchctl kickstart exception: {e}")

    # 2. Direct spawn fallback
    py_bin = "/opt/homebrew/bin/python3" if os.path.exists("/opt/homebrew/bin/python3") else sys.executable
    if os.path.exists(DAEMON_PATH):
        try:
            log(f"Spawning proxy directly: {py_bin} {DAEMON_PATH}")
            subprocess.Popen(
                [py_bin, DAEMON_PATH, "--port", str(PROXY_PORT)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            for _ in range(10):
                time.sleep(0.3)
                if is_proxy_healthy():
                    log("Proxy successfully started via direct spawn")
                    return True
        except Exception as e:
            log(f"Direct spawn exception: {e}")

    log("⚠️ Could not verify proxy startup")
    return False

def background_watchdog():
    while True:
        try:
            if not is_proxy_healthy():
                ensure_proxy_running()
        except Exception as e:
            log(f"Watchdog loop error: {e}")
        time.sleep(5)

def send_response(req_id, result=None, error=None):
    resp = {"jsonrpc": "2.0", "id": req_id}
    if error is not None:
        resp["error"] = error
    else:
        resp["result"] = result if result is not None else {}
    data = json.dumps(resp) + "\n"
    sys.stdout.write(data)
    sys.stdout.flush()

def main():
    log("Claude Proxy Watchdog started")
    # Immediate start on launch
    ensure_proxy_running()

    # Background thread to monitor continuously
    t = threading.Thread(target=background_watchdog, daemon=True)
    t.start()

    # Process stdio MCP JSON-RPC protocol
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue

        try:
            msg = json.loads(line)
        except Exception:
            continue

        req_id = msg.get("id")
        method = msg.get("method")

        if not method:
            continue

        if method == "initialize":
            send_response(req_id, {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {}
                },
                "serverInfo": {
                    "name": "claude-proxy-watchdog",
                    "version": "1.0.0"
                }
            })
        elif method == "notifications/initialized":
            # Notification: no response
            pass
        elif method == "ping":
            send_response(req_id, {})
        elif method == "tools/list":
            send_response(req_id, {
                "tools": [
                    {
                        "name": "check_proxy_status",
                        "description": "Checks whether the Claude local loopback proxy is running and healthy",
                        "inputSchema": {
                            "type": "object",
                            "properties": {}
                        }
                    }
                ]
            })
        elif method == "tools/call":
            params = msg.get("params", {})
            name = params.get("name")
            if name == "check_proxy_status":
                healthy = is_proxy_healthy()
                status_text = "Proxy is ACTIVE and HEALTHY on http://127.0.0.1:8080" if healthy else "Proxy is STOPPED or UNRESPONSIVE"
                send_response(req_id, {
                    "content": [
                        {
                            "type": "text",
                            "text": status_text
                        }
                    ]
                })
            else:
                send_response(req_id, error={"code": -32601, "message": f"Method {name} not found"})
        else:
            if req_id is not None:
                send_response(req_id, {})

    log("Claude Proxy Watchdog exiting")

if __name__ == "__main__":
    main()
