#!/bin/bash
# Health check for Mike's core. Prints status codes and the /status JSON only.
# The token is read from .env by this script and is never displayed.
echo -n "no-token status code (expect 401): "
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8787/status
TOKEN=$(grep '^MIKE_TOKEN=' .env | cut -d= -f2-)
echo -n "with-token /status: "
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8787/status
echo
