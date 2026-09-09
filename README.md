# ThreadVault 0.6

ThreadVault is a local-first Flutter Android app for downloading media from Threads posts that the signed-in user is already authorized to view.

## Implemented in this build

- Public Threads post resolution through an embedded browser
- Private-post support through the user's own Threads login
- **No Threads password storage**: login happens directly inside the Threads web page
- Batch input: paste many Threads links at once
- Multiple videos per post
- Images / carousel candidate extraction
- Progressive `video_versions` extraction, with DASH MP4 fallback
- Automatic JSON/HTML URL unescaping (`\/`, `\u0026`, HTML entities, etc.)
- Smart filename templates: `{author}`, `{postId}`, `{index}`
- Optional caption `.txt` sidecar files
- On-device download history with status/error tracking
- Share downloaded media from History
- Session reconnect workflow
- Session status indicator
- Automatic session expiry / cookie wipe with configurable TTL
- Explicit “Delete session now” control
- Premium Material 3 dark UI
- Optional FastAPI resolver backend for public/authorized local deployments
- Dockerfile + docker-compose for the optional API
- Backend parser regression tests

## Everyday workflow

1. Open **Private** once and sign in to Threads if private content is needed.
2. Return to **Download**.
3. Paste one or many `threads.com/@user/post/...` links.
4. Tap **Download media** / **Download batch**.
5. ThreadVault opens each post in its embedded browser, extracts the media data locally, downloads every resolved item, and records it in **History**.

Public posts do not require a connected Threads session. Private posts only work if the connected Threads account can already view them.

## Privacy model

The mobile app is deliberately local-first. Threads authentication cookies remain in the app WebView cookie jar. ThreadVault stores only non-secret session metadata in encrypted device storage to track connection age. The user's Threads password is never collected or sent to the ThreadVault backend.

When auto-delete is enabled, ThreadVault checks session age periodically and clears the embedded-browser cookies after the configured lifetime. The user can also wipe the session immediately from the Private tab.

## Mobile development

Requirements: Flutter 3.24+ / Dart 3.4+, Android SDK, JDK 17.

```bash
cd mobile
flutter pub get
flutter run
```

An Android project scaffold is included under `mobile/android`. If a local Flutter version requires regenerated platform files, run `flutter create . --platforms android` from `mobile/` and keep the existing `lib/` and `pubspec.yaml`.

### Release APK

Before distributing a release, replace the debug signing configuration with your own Android keystore, then:

```bash
flutter build apk --release
```

## Optional API

The mobile app does not need the API for its private-session flow. The API exists for future sync, public resolving, or a self-hosted deployment.

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pytest -q
uvicorn app.main:app --reload --port 8000
```

Or:

```bash
docker compose up --build
```

Set a strong `SESSION_ENCRYPTION_KEY` before storing any server-side authorized session blob.

## Important limitations

Threads can change its web payload structure without notice. The resolver is isolated in `mobile/lib/services/threads_parser.dart` and `backend/app/services/threads_provider.py` so parsing rules can be updated without redesigning the app.

Signed Instagram/Meta CDN media URLs also expire. ThreadVault obtains them immediately before downloading rather than saving them as permanent source URLs.

This build does not circumvent private-account controls. It only processes content visible to the connected account.
