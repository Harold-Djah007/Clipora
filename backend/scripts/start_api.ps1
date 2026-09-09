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

function Get-LanIPv4 {
    try {
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike "127.*" -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.PrefixOrigin -ne "WellKnown"
            } |
            Select-Object -ExpandProperty IPAddress -Unique
    } catch {
        @()
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

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "ffmpeg was not found on PATH. YouTube/X/Facebook HLS fallback needs it." -ForegroundColor Yellow
    Write-Host "Install with: winget install Gyan.FFmpeg" -ForegroundColor Yellow
}

try {
    New-NetFirewallRule -DisplayName "Clipora Backend $selected" -Direction Inbound -Protocol TCP -LocalPort $selected -Action Allow -ErrorAction Stop | Out-Null
    Write-Host "Opened Windows firewall for TCP $selected." -ForegroundColor DarkGray
} catch {
    Write-Host "Could not add a firewall rule automatically. If the phone cannot connect, allow TCP $selected inbound in Windows Defender Firewall." -ForegroundColor Yellow
}

$lan = @(Get-LanIPv4)
Write-Host "Starting Clipora backend on http://0.0.0.0:$selected" -ForegroundColor Cyan
Write-Host "USB testing: adb reverse tcp:$selected tcp:$selected then use http://127.0.0.1:$selected" -ForegroundColor Yellow
if ($lan.Count -gt 0) {
    foreach ($ip in $lan) {
        Write-Host "Phone on same Wi-Fi: Settings → Resolver URL → http://$ip`:$selected" -ForegroundColor Green
    }
} else {
    Write-Host "Phone on same Wi-Fi: Settings → Resolver URL → http://YOUR-PC-LAN-IP:$selected" -ForegroundColor Green
}
Write-Host "Keep this terminal open while testing the mobile app/API." -ForegroundColor Yellow
& ".\.venv\Scripts\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port $selected
