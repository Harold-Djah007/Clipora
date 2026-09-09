# Branch test command

```powershell
cd "C:\Users\A S U S\Desktop\Clipora"
git fetch origin
git switch feature/universal-resolver-foundation
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pytest -q
```
