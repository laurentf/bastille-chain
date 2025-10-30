@echo off
echo 🏰 Starting Bastille Node 2 (Relay)
echo Port: 8002
echo Role: Pure Relay Node
echo Bootstrap: 127.0.0.1:8001
echo.

cd /d "%~dp0\.."
set MIX_ENV=node2
mix run --no-halt --config config/node2.exs

pause