# Universal Resolver Status

## Done in this branch

- Pushed current 0.8.3 baseline to GitHub.
- Added backend platform detection.
- Added yt-dlp universal resolver foundation.
- Added universal resolve and detect endpoints.
- Updated download jobs to preserve platform/source/quality metadata.
- Added backend tests and GitHub Actions backend test workflow.

## Needs phone/local testing next

- Run backend tests locally.
- Start backend API.
- Test `/api/detect` with each platform.
- Test `/api/resolve/universal` with public links.
- Then wire Flutter UI to backend universal resolver.

## Do not regress

- Existing Threads Smart Capture must remain the main fallback for private/authorized Threads posts.
- Video posts must not save poster JPGs.
- User should not be forced to choose Video/Post/Photos every time.
