#!/bin/bash
# Wrapper script to start Chatwoot dev environment with proxy support

# Explicitly export proxy variables
export HTTPS_PROXY=http://172.24.160.1:10809
export HTTP_PROXY=http://172.24.160.1:10809

echo "Starting Chatwoot with proxy configuration..."
echo "HTTPS_PROXY: $HTTPS_PROXY"
echo "HTTP_PROXY: $HTTP_PROXY"
echo ""

# Start foreman
cd "$(dirname "$0")"
exec foreman start -f Procfile.dev
