# ThreadVault Security Notes

- Do not collect Threads/Instagram passwords in app-owned forms.
- Authenticate only on the official Threads web origin inside the embedded browser.
- Keep private-session cookies on-device by default.
- Never log cookie values, authorization headers, resolved private HTML, or signed CDN URLs.
- Signed media URLs should be treated as short-lived secrets and used immediately.
- Auto-delete should clear the WebView cookie jar and secure session metadata.
- The optional backend session endpoint is intended for self-hosted/controlled deployments only and encrypts supplied session blobs at rest in memory; production deployments should use a persistent secret store and authentication.
- Resolver inputs are restricted to HTTPS Threads hosts to reduce SSRF risk.
- Private content must only be processed when the connected account is already allowed to view it.
