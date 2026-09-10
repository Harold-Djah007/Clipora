# Local backend + phone test

Use this exact cycle from the Windows repo folder. Keep the backend terminal open while the second terminal builds and installs the APK.

## First PowerShell

```powershell
cd "C:\Users\A S U S\Desktop\threadvault_premium_0.6.0\threadvault"

git switch cursor/tiktok-notify-harden-2f1d
git pull origin cursor/tiktok-notify-harden-2f1d
git log -1 --oneline

cd backend
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m pytest -q
powershell -ExecutionPolicy Bypass -File ".\scripts\start_api.ps1"
```

Leave that terminal open. If port 8010 is already taken, start it pinned:

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\start_api.ps1" -Ports 8010
```

## Second PowerShell

```powershell
Invoke-RestMethod "http://127.0.0.1:8010/health"

& "C:\Android\Sdk\platform-tools\adb.exe" reverse --remove-all
& "C:\Android\Sdk\platform-tools\adb.exe" reverse tcp:8010 tcp:8010

cd "C:\Users\A S U S\Desktop\threadvault_premium_0.6.0\threadvault\mobile"

flutter clean
flutter pub get
flutter test
flutter build apk --debug --no-pub --dart-define=CLIPORA_RESOLVER_URL=http://127.0.0.1:8010

& "C:\Android\Sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-debug.apk"
```

Open Clipora once and allow notifications if Android asks. Then use a fresh public TikTok video:

TikTok → Share → More → Clipora

Clipora should return you to TikTok immediately, continue in the background, and show a concise success or error notification.

## If Download says the resolver is unreachable

This is a connection failure, not a TikTok extraction failure. The APK cannot reach the backend on port 8010.

First backend PowerShell:

```powershell
cd "C:\Users\A S U S\Desktop\threadvault_premium_0.6.0\threadvault\backend"
Invoke-RestMethod "http://127.0.0.1:8010/health"
```

If that fails, start the backend and keep the terminal open:

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\start_api.ps1" -Ports 8010
```

In another PowerShell:

```powershell
& "C:\Android\Sdk\platform-tools\adb.exe" devices

& "C:\Android\Sdk\platform-tools\adb.exe" reverse --remove-all
& "C:\Android\Sdk\platform-tools\adb.exe" reverse tcp:8010 tcp:8010
& "C:\Android\Sdk\platform-tools\adb.exe" reverse --list
```

You should see a mapping containing:

```text
tcp:8010 tcp:8010
```

On the phone, open Chrome and visit:

```text
http://127.0.0.1:8010/health
```

Expected:

```json
{"ok":true,"service":"clipora","version":"2.0.6"}
```

If that appears, return to Clipora and retry Download. No rebuild is required just to fix the current connection.

## Optional detect smoke test

```powershell
Invoke-RestMethod -Method Post "http://127.0.0.1:8010/api/detect" -ContentType "application/json" -Body '{"url":"https://x.com/user/status/1234567890"}'
```
