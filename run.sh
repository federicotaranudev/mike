#!/bin/bash
# Start Mike's core on this PC (loopback only). Ctrl+C stops it.
cd "$(dirname "$0")"
exec .venv/bin/python -m uvicorn agent.api:app --host 127.0.0.1 --port 8787
