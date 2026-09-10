# Current branch

`feature/universal-resolver-foundation` contains the first GitHub-based Clipora upgrade after the user pushed the repository.

It is resolver-only: Flutter and the native Android share service use `/api/resolve/universal`, including for Threads, and HLS links can fall back to a local `/api/files` download.

Phone testing for the current harden pass uses `cursor/tiktok-notify-harden-2f1d` on top of that base. Follow `local-backend-test.md` for the PowerShell cycle.
