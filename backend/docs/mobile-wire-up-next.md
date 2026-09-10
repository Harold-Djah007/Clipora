# Mobile wire-up next

The backend branch is only the first foundation. The Flutter app still needs a mobile service layer to call it.

## Required Flutter additions next

- `UniversalPlatformDetector`
- `UniversalResolverService`
- platform icons/chips in the paste screen
- queue cards showing platform, media type, quality, and progress
- fallback routing:
  - Threads/public → universal resolver
  - public universal links → backend `/api/resolve/universal`

## Testing command after mobile wire-up

```powershell
cd "C:\Users\A S U S\Desktop\Clipora\mobile"
flutter clean
flutter pub get
flutter test
flutter build apk --debug --no-pub
& "C:\Android\Sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-debug.apk"
```
