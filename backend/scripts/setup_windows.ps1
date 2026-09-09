param(
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"

Write-Host "Clipora backend Windows setup" -ForegroundColor Cyan
Write-Host "This project should run on Python 3.12/3.13 on Windows. Python 3.14 can force pydantic-core to compile from Rust and fail when Visual C++ link.exe is missing." -ForegroundColor Yellow
Write-Host "The backend uses port 8010 by default because Windows can reserve/block port 8000 and cause WinError 10013." -ForegroundColor Yellow

function Get-PythonMinorVersion {
    param([string]$Exe)
    try {
        $version = & $Exe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
        if ($LASTEXITCODE -eq 0) { return ($version | Select-Object -First 1).Trim() }
    } catch {}
    return $null
}

function Accept-Python {
    param([string]$Exe)
    if (-not $Exe) { return $null }
    if (-not (Test-Path $Exe) -and -not (Get-Command $Exe -ErrorAction SilentlyContinue)) { return $null }
    $version = Get-PythonMinorVersion $Exe
    if ($version -eq "3.12" -or $version -eq "3.13") { return $Exe }
    return $null
}

function Resolve-Python {
    param([string]$Requested)

    if ($Requested) {
        $picked = Accept-Python $Requested
        if ($picked) { return $picked }
        throw "The Python path supplied with -Python is not Python 3.12/3.13: $Requested"
    }

    # First ask the Python launcher. After a fresh winget install, the launcher can
    # sometimes miss the new runtime until a new PowerShell window is opened, so the
    # script also checks the real install paths below.
    foreach ($minor in @("3.12", "3.13")) {
        try {
            $exe = & py "-$minor" -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $picked = Accept-Python (($exe | Select-Object -First 1).Trim())
                if ($picked) { return $picked }
            }
        } catch {}
    }

    $candidatePaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "$env:ProgramFiles\Python313\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe",
        "${env:ProgramFiles(x86)}\Python313\python.exe"
    ) | Where-Object { $_ -and $_.Trim() }

    foreach ($path in $candidatePaths) {
        $picked = Accept-Python $path
        if ($picked) { return $picked }
    }

    foreach ($command in @("python3.12", "python3.13", "python")) {
        try {
            $source = (Get-Command $command -ErrorAction Stop).Source
            $picked = Accept-Python $source
            if ($picked) { return $picked }
        } catch {}
    }

    Write-Host "Known Python launcher runtimes:" -ForegroundColor Yellow
    try { py -0p } catch { Write-Host "Python launcher could not list runtimes." -ForegroundColor Yellow }
    throw "Python 3.12 or 3.13 was not found by this shell. Open a new PowerShell window or pass the path explicitly, for example: powershell -ExecutionPolicy Bypass -File .\scripts\setup_windows.ps1 -Python `"$env:LOCALAPPDATA\Programs\Python\Python312\python.exe`""
}

$py = Resolve-Python $Python
Write-Host "Using: $py" -ForegroundColor Green

if (Test-Path ".venv") {
    Remove-Item -Recurse -Force ".venv"
}

& $py -m venv .venv
& ".\.venv\Scripts\python.exe" -m pip install --upgrade pip setuptools wheel
& ".\.venv\Scripts\python.exe" -m pip install -r requirements.txt
Write-Host "Backend setup complete. Run tests with:" -ForegroundColor Green
Write-Host ".\.venv\Scripts\python.exe -m pytest -q" -ForegroundColor White
Write-Host "Start API with:" -ForegroundColor Green
Write-Host "powershell -ExecutionPolicy Bypass -File .\scripts\start_api.ps1" -ForegroundColor White
Write-Host "Manual fallback:" -ForegroundColor Green
Write-Host ".\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8010" -ForegroundColor White
