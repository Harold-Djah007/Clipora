# Resolver provider notes

The user-provided Telegram bot examples inspired the backend direction, but Clipora is not a Telegram bot. Clipora's backend exposes resolver APIs that the Flutter app can use.

## Used from the supplied code

- `yt-dlp` as the universal resolver engine.
- Best MP4-oriented format preference.
- Clear failure handling for unsupported/private/restricted links.
- Size/quality metadata for UI and queue display.

## Not used

- Bot token handling.
- Telegram upload flow.
- Watermark-removal-specific TikTok endpoint behavior.
- Password or cookie collection from users.
