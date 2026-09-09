# Windows backend setup fix

The error below means the backend virtual environment was created with Python 3.14 and pip tried to build `pydantic-core` from source:

```text
error: linker `link.exe` not found
Failed building wheel for pydantic-core
```

Use Python 3.12 or 3.13 for the backend on Windows. This avoids the Visual C++ linker problem and uses normal prebuilt wheels.

```powershell
cd "C:\Users\A S U S\Desktop\threadvault_premium_0.6.0\threadvault\backend"
powershell -ExecutionPolicy Bypass -File ".\scripts\setup_windows.ps1"
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

Do not run plain `pytest` or plain `uvicorn` until the virtual environment install succeeds. The safer commands call them through `.venv\Scripts\python.exe -m ...`.
