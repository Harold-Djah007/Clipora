# Platform session configuration

Clipora resolves public/shareable media only. TikTok, Instagram, Threads, Facebook,
and Snapchat sometimes return a home or login shell to cloud datacenter IPs even
when the same post opens in an already-signed-in phone app.

For a field deployment, create a separate low-privilege social account that is used
only by the resolver. Export its cookies in Netscape `cookies.txt` format, then add
that file in Render under **Environment > Secret Files** with the filename
`cookies.txt`. Render mounts it at `/etc/secrets/cookies.txt`, which Clipora discovers
automatically. Do not upload the cookies of a personal or administrator account.

An optional outbound proxy can be configured as the secret environment variable
`CLIPORA_OUTBOUND_PROXY`. HTTP, HTTPS, SOCKS4, SOCKS5, and SOCKS5H URLs are accepted;
HTTP(S) is used by both page requests and yt-dlp. Never commit proxy credentials or
cookie contents to Git.

Open `/health` after deployment. `cookies_configured` and `proxy_configured` report
only whether each mechanism is enabled; no secret value is returned.
