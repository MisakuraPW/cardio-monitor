param(
  [int]$Port = 8000
)
$env:PYTHONPATH = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$PSScriptRoot\.venv\Scripts\python.exe" -m uvicorn app.main:app --reload --port $Port
