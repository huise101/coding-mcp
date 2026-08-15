@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start_chatgpt_mcp.ps1"

echo.
echo ===== Current startup info =====
set SESSION_FILE=%SCRIPT_DIR%.runtime\chatgpt-mcp-last-session.txt
if exist "%SESSION_FILE%" (
	type "%SESSION_FILE%"
) else (
	echo Session file not found: %SESSION_FILE%
)

echo.
echo Tip: mcp_url is the ChatGPT MCP Server URL, oauth_password is the OAuth password.
pause
endlocal
