# Clipora Security Notes

- Clipora accepts only supported `http`/`https` social links; unknown hosts are rejected before extraction.
- The Android app does not open social login pages, collect passwords, or upload session cookies.
- Hosted resolver URLs must use HTTPS. Cleartext HTTP is accepted only for localhost, emulator, and private LAN testing.
- Resolved media URLs and temporary file tokens should be treated as short-lived data and must not be logged in production.
- Private or restricted posts fail normally; Clipora does not bypass access controls.
- Clipora does not include watermark-removal behavior.
- Deploy the resolver behind normal TLS, authentication/rate limiting where appropriate, and routine dependency updates.
