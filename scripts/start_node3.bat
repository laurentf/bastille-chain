@echo off
echo 🏰 Starting Bastille Node 3 (Mining)
echo Port: 8003
echo Role: Mining + Relay
echo Bootstrap: 127.0.0.1:8001, 127.0.0.1:8002
echo.

cd /d "%~dp0\.."
set MIX_ENV=node3
mix run --no-halt --config config/node3.exs

pause