# Current branch

`feature/universal-resolver-foundation` contains the first GitHub-based Clipora upgrade after the user pushed the repository.

It is resolver-only: Flutter and the native Android share service use `/api/resolve/universal`, including for Threads, and HLS links can fall back to a local `/api/files` download.
