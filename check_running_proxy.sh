#!/bin/bash
echo "Checking running Rails server for proxy configuration..."
echo ""

# Wait for Rails to start
sleep 3

# Get Rails server PID
RAILS_PID=$(pgrep -f "puma.*chatwoot" | head -1)

if [ -z "$RAILS_PID" ]; then
  echo "❌ Rails server not running"
  exit 1
fi

echo "Rails server PID: $RAILS_PID"
echo ""

# Check environment
PROXY_CHECK=$(cat /proc/$RAILS_PID/environ | tr '\0' '\n' | grep "HTTPS_PROXY")

if [ -n "$PROXY_CHECK" ]; then
  echo "✅ PROXY CONFIGURED in running Rails process:"
  cat /proc/$RAILS_PID/environ | tr '\0' '\n' | grep -E "HTTPS_PROXY|HTTP_PROXY"
  echo ""
  echo "Captain should be fast now!"
else
  echo "❌ PROXY NOT FOUND in running Rails process"
  echo ""
  echo "Troubleshooting:"
  echo "1. Make sure you restarted foreman after updating bin/rails"
  echo "2. Try using: ./start_dev.sh instead of foreman start"
fi
