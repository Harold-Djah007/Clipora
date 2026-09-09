# Local backend test

```powershell
cd "C:\Users\A S U S\Desktop\Clipora\backend"
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pytest -q
uvicorn app.main:app --reload --port 8000
```

Then test:

```powershell
Invoke-RestMethod -Method Post "http://127.0.0.1:8000/api/detect" -ContentType "application/json" -Body '{"url":"https://x.com/user/status/1234567890"}'
```
