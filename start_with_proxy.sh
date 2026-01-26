#!/bin/bash
# Simple script to start Chatwoot with proxy

cd "$(dirname "$0")"

# Export proxy for all child processes
export HTTPS_PROXY=http://172.24.160.1:10809
export HTTP_PROXY=http://172.24.160.1:10809

echo "=========================================="
echo "Starting Chatwoot with Proxy Configuration"
echo "=========================================="
echo "HTTPS_PROXY: $HTTPS_PROXY"
echo "HTTP_PROXY: $HTTP_PROXY"
echo "=========================================="
echo ""

# Start foreman (which will inherit these variables)
exec foreman start -f Procfile.dev
