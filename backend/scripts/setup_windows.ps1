param(
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"

Write-Host "Clipora backend Windows setup" -ForegroundColor Cyan
Write-Host "This project should run on Python 3.12/3.13 on Windows. Python 3.14 can force pydantic-core to compile from Rust and fail when Visual C++ link.exe is missing." -ForegroundColor Yellow

function Resolve-Python {
    param([string]$Requested)
    if ($Requested) { return $Requested }
    $candidates = @("py -3.12", "py -3.13", "python")
    foreach ($candidate in $candidates) {
        try {
            $version = Invoke-Expression "$candidate -c \"import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')\"" 2>$null
            if ($LASTEXITCODE -eq 0 -and ($version -eq "3.12" -or $version -eq "3.13")) {
                return $candidate
            }
        } catch {}
    }
    throw "Python 3.12 or 3.13 was not found. Install Python 3.12 from python.org, then rerun this script."
}

$py = Resolve-Python $Python
Write-Host "Using: $py" -ForegroundColor Green

if (Test-Path ".venv") {
    Remove-Item -Recurse -Force ".venv"
}

Invoke-Expression "$py -m venv .venv"
& ".\.venv\Scripts\python.exe" -m pip install --upgrade pip setuptools wheel
& ".\.venv\Scripts\python.exe" -m pip install -r requirements.txt
Write-Host "Backend setup complete. Run tests with:" -ForegroundColor Green
Write-Host ".\.venv\Scripts\python.exe -m pytest -q" -ForegroundColor White
Write-Host "Start API with:" -ForegroundColor Green
Write-Host ".\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000" -ForegroundColor White
