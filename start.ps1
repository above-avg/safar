$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$pythonPath = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonPath)) {
    Write-Host 'Create the virtual environment and install requirements first. See README.md.'
    exit 1
}
& $pythonPath -m uvicorn backend.app:app --host 127.0.0.1 --port 8000
