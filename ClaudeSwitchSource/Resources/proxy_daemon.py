#!/usr/bin/env python3
import sys
import argparse
import http.server
import socketserver
import time
import json
import socket
import urllib3
import uuid

# High-performance connection pool with upstream keep-alive
pool = urllib3.PoolManager(
    maxsize=30,
    timeout=urllib3.Timeout(connect=6.0, read=180.0),
    retries=urllib3.util.Retry(total=2, backoff_factor=0.2, raise_on_status=False)
)

class FastProxyHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    target_url = "http://127.0.0.1:8000"
    target_model = ""

    def log_message(self, format, *args):
        ts = time.strftime("%H:%M:%S")
        msg = format % args
        sys.stdout.write(f"[{ts}] {msg}\n")
        sys.stdout.flush()

    def do_GET(self):
        self._forward()

    def do_POST(self):
        self._forward()

    def do_HEAD(self):
        self._forward()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, HEAD")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Connection", "keep-alive")
        self.send_header("Keep-Alive", "timeout=120, max=1000")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _forward(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        # Model name translation & tool casing map
        tool_map = {}
        if body:
            try:
                payload = json.loads(body.decode("utf-8"))
                # Build canonical tool map for case-insensitive & hyphen-normalized resolution
                if "tools" in payload and isinstance(payload["tools"], list):
                    for t in payload["tools"]:
                        t_name = t.get("name")
                        if t_name:
                            tool_map[t_name.lower()] = t_name
                            tool_map[t_name.lower().replace("-", "_")] = t_name
                            tool_map[t_name.lower().replace("__", "_")] = t_name

                if self.target_model and "model" in payload:
                    orig_model = payload["model"]
                    payload["model"] = self.target_model
                    body = json.dumps(payload).encode("utf-8")
                    if orig_model != self.target_model:
                        self.log_message("Rewrote model '%s' -> '%s'", orig_model, self.target_model)
            except Exception:
                pass

        if self._is_openai_target() and body:
            self._forward_openai_bridge(body, tool_map)
            return

        target = self.target_url.rstrip("/") + self.path

        # Forward request headers (excluding hop-by-hop headers)
        fwd_headers = {}
        for key, val in self.headers.items():
            k_lower = key.lower()
            if k_lower not in ["host", "content-length", "transfer-encoding", "connection"]:
                fwd_headers[key] = val
        fwd_headers["Connection"] = "keep-alive"

        # Ensure both Authorization and x-api-key are set if either is provided
        auth_hdr = fwd_headers.get("Authorization") or fwd_headers.get("authorization")
        x_key_hdr = fwd_headers.get("x-api-key") or fwd_headers.get("X-Api-Key")
        if auth_hdr and not x_key_hdr:
            if auth_hdr.lower().startswith("bearer "):
                fwd_headers["x-api-key"] = auth_hdr[7:].strip()
        elif x_key_hdr and not auth_hdr:
            fwd_headers["Authorization"] = f"Bearer {x_key_hdr}"

        # OpenRouter client metadata headers
        if "openrouter.ai" in self.target_url.lower():
            if "HTTP-Referer" not in fwd_headers and "http-referer" not in fwd_headers:
                fwd_headers["HTTP-Referer"] = "https://claude.ai"
            if "X-Title" not in fwd_headers and "x-title" not in fwd_headers:
                fwd_headers["X-Title"] = "Claude Desktop"

        try:
            t0 = time.time()
            resp = pool.request(
                self.command,
                target,
                body=body,
                headers=fwd_headers,
                preload_content=False,
                decode_content=False
            )
            ttfb = time.time() - t0

            # Send HTTP status
            self.send_response(resp.status)

            # Determine if this response should use chunked transfer encoding
            content_type = resp.headers.get("Content-Type", "").lower()
            is_stream = "text/event-stream" in content_type or "chunked" in resp.headers.get("Transfer-Encoding", "").lower()
            resp_content_length = resp.headers.get("Content-Length")

            # Forward response headers
            for header, val in resp.headers.items():
                h_lower = header.lower()
                if h_lower not in ["transfer-encoding", "content-length", "connection", "keep-alive"]:
                    self.send_header(header, val)

            self.send_header("Connection", "keep-alive")
            self.send_header("Keep-Alive", "timeout=120, max=1000")

            if resp_content_length is not None and not is_stream:
                resp_body = resp.data
                if tool_map and b"tool_use" in resp_body:
                    try:
                        text = resp_body.decode("utf-8")
                        modified = False
                        for lower_name, canonical_name in tool_map.items():
                            if lower_name != canonical_name:
                                p1 = f'"name":"{lower_name}"'
                                r1 = f'"name":"{canonical_name}"'
                                if p1 in text:
                                    text = text.replace(p1, r1)
                                    modified = True
                                p2 = f'"name": "{lower_name}"'
                                r2 = f'"name": "{canonical_name}"'
                                if p2 in text:
                                    text = text.replace(p2, r2)
                                    modified = True
                        if modified:
                            resp_body = text.encode("utf-8")
                            self.log_message("Normalized tool use casing in fixed response")
                    except Exception:
                        pass
                self.send_header("Content-Length", str(len(resp_body)))
                self.end_headers()
                try:
                    self.wfile.write(resp_body)
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError, socket.error):
                    self.log_message("Client disconnected while reading fixed response")
            else:
                # Chunked streaming (essential for SSE / zero-latency tokens)
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()

                chunk_count = 0
                try:
                    for chunk in resp.stream(amt=None, decode_content=False):
                        if chunk:
                            chunk_count += 1
                            if tool_map and b"tool_use" in chunk:
                                try:
                                    chunk_text = chunk.decode("utf-8")
                                    modified = False
                                    for lower_name, canonical_name in tool_map.items():
                                        if lower_name != canonical_name:
                                            p1 = f'"name":"{lower_name}"'
                                            r1 = f'"name":"{canonical_name}"'
                                            if p1 in chunk_text:
                                                chunk_text = chunk_text.replace(p1, r1)
                                                modified = True
                                            p2 = f'"name": "{lower_name}"'
                                            r2 = f'"name": "{canonical_name}"'
                                            if p2 in chunk_text:
                                                chunk_text = chunk_text.replace(p2, r2)
                                                modified = True
                                    if modified:
                                        chunk = chunk_text.encode("utf-8")
                                        self.log_message("Normalized tool use casing in stream")
                                except Exception:
                                    pass

                            # Strip [DONE] marker if present (OpenRouter sends [DONE] at the end of SSE)
                            if b"[DONE]" in chunk:
                                lines = chunk.split(b"\n")
                                filtered = [l for l in lines if l.strip() != b"data: [DONE]" and l.strip() != b"event: data"]
                                chunk = b"\n".join(filtered)
                                if not chunk.strip():
                                    continue

                            chunk_len = f"{len(chunk):X}\r\n".encode("ascii")
                            self.wfile.write(chunk_len + chunk + b"\r\n")
                            self.wfile.flush()

                    # Send final zero-length chunk to cleanly end HTTP/1.1 chunked stream
                    self.wfile.write(b"0\r\n\r\n")
                    self.wfile.flush()
                    total_dur = time.time() - t0
                    self.log_message("Stream completed: %d chunks in %.2fs (TTFB: %.2fs)", chunk_count, total_dur, ttfb)
                except (BrokenPipeError, ConnectionResetError, socket.error):
                    self.log_message("Client cancelled stream after %d chunks (%.2fs)", chunk_count, time.time() - t0)

            resp.release_conn()

        except urllib3.exceptions.TimeoutError as e:
            self.log_message("Upstream timeout error connecting to %s: %s", target, str(e))
            self._send_error_safe(504, f"Gateway Timeout connecting to upstream: {str(e)}")
        except Exception as e:
            self.log_message("Error proxying request to %s: %s", target, str(e))
            self._send_error_safe(502, f"Loopback Forwarder Error connecting to {target}: {str(e)}")

    def _is_openai_target(self):
        t = self.target_url.lower()
        return "chat/completions" in t or "codecraftapi.com" in t or getattr(self, "force_openai_bridge", False)

    def _write_chunk(self, data_bytes):
        chunk_len = f"{len(data_bytes):X}\r\n".encode("ascii")
        self.wfile.write(chunk_len + data_bytes + b"\r\n")
        self.wfile.flush()

    def _forward_openai_bridge(self, body, tool_map):
        try:
            payload = json.loads(body.decode("utf-8")) if body else {}
        except Exception:
            payload = {}

        # Resolve upstream chat completions URL
        clean_target = self.target_url.rstrip("/")
        if clean_target.endswith("/chat/completions"):
            target = clean_target
        elif clean_target.endswith("/v1"):
            target = clean_target + "/chat/completions"
        else:
            target = clean_target + "/v1/chat/completions"

        # Translate Anthropic messages -> OpenAI messages
        oai_messages = []
        if "system" in payload and payload["system"]:
            sys_val = payload["system"]
            if isinstance(sys_val, list):
                sys_text = "\n".join([b.get("text", "") for b in sys_val if isinstance(b, dict) and b.get("type") == "text"])
            else:
                sys_text = str(sys_val)
            oai_messages.append({"role": "system", "content": sys_text})

        for m in payload.get("messages", []):
            role = m.get("role", "user")
            content = m.get("content", "")
            if isinstance(content, list):
                parts = []
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "text":
                        parts.append(b.get("text", ""))
                    elif isinstance(b, str):
                        parts.append(b)
                content = "\n".join(parts)
            oai_messages.append({"role": role, "content": content})

        model = self.target_model if self.target_model else payload.get("model", "claude-opus-5.5")
        is_stream = payload.get("stream", True)
        oai_req = {
            "model": model,
            "messages": oai_messages,
            "stream": is_stream
        }
        if "max_tokens" in payload:
            oai_req["max_tokens"] = payload["max_tokens"]
        if "temperature" in payload:
            oai_req["temperature"] = payload["temperature"]

        # Forward authorization token
        auth_token = self.headers.get("x-api-key") or self.headers.get("authorization") or ""
        if auth_token.lower().startswith("bearer "):
            auth_token = auth_token[7:].strip()

        fwd_headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {auth_token}",
            "Connection": "keep-alive"
        }

        try:
            t0 = time.time()
            resp = pool.request(
                "POST",
                target,
                body=json.dumps(oai_req).encode("utf-8"),
                headers=fwd_headers,
                preload_content=False,
                decode_content=False
            )
            ttfb = time.time() - t0

            if resp.status != 200:
                err_data = resp.data.decode("utf-8", errors="ignore")
                self.log_message("OpenAI bridge upstream error (%d): %s", resp.status, err_data[:200])
                self._send_error_safe(resp.status, f"Upstream OpenAI API error: {err_data[:200]}")
                resp.release_conn()
                return

            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream" if is_stream else "application/json")
            self.send_header("Connection", "keep-alive")
            self.send_header("Keep-Alive", "timeout=120, max=1000")

            if is_stream:
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()

                msg_id = f"msg_{uuid.uuid4().hex[:20]}"
                first_chunk = True
                buffer = ""
                chunk_count = 0
                total_tokens = 0

                try:
                    for raw_chunk in resp.stream(amt=None, decode_content=False):
                        buffer += raw_chunk.decode("utf-8", errors="ignore")
                        while "\n" in buffer:
                            line, buffer = buffer.split("\n", 1)
                            line = line.strip()
                            if line.startswith("data:"):
                                data_str = line[5:].strip()
                                if data_str == "[DONE]":
                                    continue
                                try:
                                    data = json.loads(data_str)
                                    delta = data["choices"][0].get("delta", {})
                                    if "content" in delta and delta["content"]:
                                        if first_chunk:
                                            first_chunk = False
                                            start_evt = f"event: message_start\ndata: {json.dumps({'type':'message_start','message':{'id':msg_id,'type':'message','role':'assistant','model':model,'content':[],'stop_reason':None,'stop_sequence':None,'usage':{'input_tokens':10,'output_tokens':0}}})}\n\n".encode("utf-8")
                                            block_start = f"event: content_block_start\ndata: {json.dumps({'type':'content_block_start','index':0,'content_block':{'type':'text','text':''}})}\n\n".encode("utf-8")
                                            self._write_chunk(start_evt)
                                            self._write_chunk(block_start)
                                        total_tokens += 1
                                        delta_evt = f"event: content_block_delta\ndata: {json.dumps({'type':'content_block_delta','index':0,'delta':{'type':'text_delta','text':delta['content']}})}\n\n".encode("utf-8")
                                        self._write_chunk(delta_evt)
                                        chunk_count += 1
                                except Exception:
                                    pass

                    if not first_chunk:
                        block_stop = f"event: content_block_stop\ndata: {json.dumps({'type':'content_block_stop','index':0})}\n\n".encode("utf-8")
                        msg_delta = f"event: message_delta\ndata: {json.dumps({'type':'message_delta','delta':{'stop_reason':'end_turn','stop_sequence':None},'usage':{'input_tokens':10,'output_tokens':total_tokens}})}\n\n".encode("utf-8")
                        msg_stop = f"event: message_stop\ndata: {json.dumps({'type':'message_stop'})}\n\n".encode("utf-8")
                        self._write_chunk(block_stop)
                        self._write_chunk(msg_delta)
                        self._write_chunk(msg_stop)

                    # Final chunked terminator
                    self.wfile.write(b"0\r\n\r\n")
                    self.wfile.flush()
                    self.log_message("OpenAI bridge stream completed: %d tokens in %.2fs (TTFB: %.2fs)", total_tokens, time.time() - t0, ttfb)
                except (BrokenPipeError, ConnectionResetError, socket.error):
                    self.log_message("Client disconnected during OpenAI bridge stream")
            else:
                resp_data = resp.data.decode("utf-8", errors="ignore")
                oai_resp = json.loads(resp_data)
                choice_text = oai_resp["choices"][0]["message"].get("content", "")
                anthropic_resp = {
                    "id": f"msg_{uuid.uuid4().hex[:20]}",
                    "type": "message",
                    "role": "assistant",
                    "model": model,
                    "content": [{"type": "text", "text": choice_text}],
                    "stop_reason": "end_turn",
                    "usage": {"input_tokens": 10, "output_tokens": len(choice_text.split())}
                }
                out_bytes = json.dumps(anthropic_resp).encode("utf-8")
                self.send_header("Content-Length", str(len(out_bytes)))
                self.end_headers()
                self.wfile.write(out_bytes)
                self.wfile.flush()

            resp.release_conn()

        except Exception as e:
            self.log_message("Error in OpenAI bridge: %s", str(e))
            self._send_error_safe(502, f"OpenAI Bridge Forwarder Error: {str(e)}")

    def _send_error_safe(self, code, msg):
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Connection", "keep-alive")
            body = json.dumps({"error": {"message": msg, "type": "gateway_error", "code": code}}).encode("utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
        except Exception:
            pass

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def main():
    parser = argparse.ArgumentParser(description="Claude Desktop High-Performance HTTP Proxy")
    parser.add_argument("--port", type=int, default=8080, help="Local port to listen on (127.0.0.1)")
    parser.add_argument("--target", type=str, required=True, help="Remote or LAN HTTP endpoint URL")
    parser.add_argument("--target-model", type=str, default="", help="Optional model ID to rewrite in request body")
    args = parser.parse_args()

    FastProxyHandler.target_url = args.target
    FastProxyHandler.target_model = args.target_model
    server_address = ("127.0.0.1", args.port)

    rewrite_info = f" (Rewriting model to '{args.target_model}')" if args.target_model else ""
    sys.stdout.write(f"🚀 High-Performance Proxy started on http://127.0.0.1:{args.port} -> Forwarding to {args.target}{rewrite_info}\n")
    sys.stdout.flush()

    try:
        httpd = ThreadedHTTPServer(server_address, FastProxyHandler)
        httpd.serve_forever()
    except KeyboardInterrupt:
        sys.stdout.write("\nProxy stopped.\n")
    except Exception as e:
        sys.stderr.write(f"Proxy Server failed: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
