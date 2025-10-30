#!/bin/bash

echo "🏰 Starting Bastille Node 1 (Bootstrap)"
echo "Port: 8001"
echo "Role: Bootstrap + Mining"
echo ""

cd "$(dirname "$0")/.."
export MIX_ENV=node1
mix run --no-halt --config config/node1.exs