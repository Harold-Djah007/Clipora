# Manual test link checklist

Use only links you are allowed to access.

## Detection-only tests

Paste one public/share link from each platform into `/api/detect` first:

- Threads
- TikTok
- Instagram
- X / Twitter
- Pinterest
- Facebook
- Snapchat public/share link
- YouTube/Shorts

## Resolve tests

After detection works, test `/api/resolve/universal` with public/share links. Expected result:

```json
{
  "platform": "x",
  "source_url": "...",
  "media": [
    {
      "media_type": "video",
      "url": "https://...mp4",
      "quality": "720p"
    }
  ]
}
```

Some platforms may return no direct MP4 or may require login/cookies. Clipora should fail clearly instead of silently saving the wrong file.
