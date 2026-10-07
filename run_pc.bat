@echo off
chcp 65001 >nul
cd /d "%~dp0"
elixir --erl "+Bc" bot.exs
echo.
pause
