@echo off
set PYTHONPATH=%~dp0
"%~dp0.venv\Scripts\python.exe" -m uvicorn app.main:app --reload --port 8000
