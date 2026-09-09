param(
    [int[]]$Ports = @(8010, 8011, 8765, 8050)
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    throw "Backend virtual environment was not found. Run: powershell -ExecutionPolicy Bypass -File .\scripts\setup_windows.ps1"
}

function Test-PortAvailable {
    param([int]$Port)
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), $Port)
        $listener.Start()
        $listener.Stop()
        return $true
    } catch {
        return $false
    }
}

$selected = $null
foreach ($port in $Ports) {
    if (Test-PortAvailable $port) {
        $selected = $port
        break
    }
    Write-Host "Port $port is blocked or already reserved. Trying next port..." -ForegroundColor Yellow
}

if (-not $selected) {
    throw "No available backend port found. Try running PowerShell as Administrator or pass another port list, for example: .\scripts\start_api.ps1 -Ports 9000,9001"
}

Write-Host "Starting Clipora backend on http://127.0.0.1:$selected" -ForegroundColor Cyan
Write-Host "Keep this terminal open while testing the mobile app/API." -ForegroundColor Yellow
& ".\.venv\Scripts\python.exe" -m uvicorn app.main:app --host 127.0.0.1 --port $selected
