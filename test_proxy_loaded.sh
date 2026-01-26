#!/bin/bash
echo "================================"
echo "Environment Variable Test"
echo "================================"
echo "HTTPS_PROXY: ${HTTPS_PROXY:-NOT SET}"
echo "HTTP_PROXY: ${HTTP_PROXY:-NOT SET}"
echo "RAILS_ENV: ${RAILS_ENV:-NOT SET}"
echo "================================"
sleep 2
