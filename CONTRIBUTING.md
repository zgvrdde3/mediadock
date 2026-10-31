# Contributing

Thank you for helping improve MediaDock.

## Before submitting a change

1. Keep media processing local and do not add account or telemetry services.
2. Do not add functionality that bypasses DRM, paywalls, or access controls.
3. Never commit Cookies, downloaded media, browser profiles, credentials, or
   personal paths.
4. Keep third-party binaries, application bundles, and build products out of
   the repository.
5. Do not make the public build copy unverified FFmpeg, ffprobe, or aria2c
   files from `Vendor/`.
6. When changing third-party behavior or build requirements, update
   `README.md`, `THIRD_PARTY_NOTICES.md`, and the relevant scripts together.
7. Explain changes that affect download speed, site compatibility, or privacy.

## Development

```sh
brew install ffmpeg aria2 node
./scripts/fetch-core.sh
./scripts/build-app.sh
```

Run the tests with:

```sh
swift test
```

Review the source-only release checklist before changing build packaging:

```sh
git status --short
git ls-files
git diff --check
```

Use clear commit messages and keep unrelated formatting changes separate from
behavioral changes.

## Issue reports

Include the macOS version, MediaDock version, yt-dlp version, and a sanitized
description of the failure. Redact links, account names, Cookies, and file paths
before posting logs.
