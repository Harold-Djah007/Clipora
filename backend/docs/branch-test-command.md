# Branch test command

```powershell
cd "C:\Users\A S U S\Desktop\threadvault_premium_0.6.0\threadvault"
git fetch origin
git switch cursor/tiktok-notify-harden-2f1d
git pull origin cursor/tiktok-notify-harden-2f1d
git log -1 --oneline
cd backend
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m pytest -q
powershell -ExecutionPolicy Bypass -File ".\scripts\start_api.ps1"
```
