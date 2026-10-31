# MediaDock

MediaDock is an unofficial, native macOS frontend for
[yt-dlp](https://github.com/yt-dlp/yt-dlp). It provides a focused SwiftUI
interface for parsing links, choosing a format, managing downloads, and keeping
the original media workflow local.

MediaDock 是一个基于 yt-dlp 的非官方 macOS 原生前端。它专注于提供清晰、
易用的链接解析与下载界面，不包含账号系统、云同步或后端服务器。

> **0.1.0 is a source-only release.** This repository does not provide a
> ready-to-use `.app` or `.dmg`. Build it locally with the steps below.

> Only download media that you own or are authorized to save. MediaDock does
> not bypass DRM, paywalls, account restrictions, or human-verification checks.

## Features

- Native SwiftUI interface with light and dark appearance support.
- Single-link and batch-link parsing, with duplicate and failure handling.
- Best quality, 1080p, and audio-only presets.
- Download queue with progress, speed, ETA, pause, resume, cancel, and retry.
- aria2 multi-connection downloads for servers that support byte ranges.
- Concurrent HLS/DASH fragment downloads.
- Parallel video/audio downloads followed by an FFmpeg merge when required.
- Optional Chrome or Edge login-state reuse from a user-authorized profile.
- Local history and Finder shortcuts.

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- Swift 6 toolchain and macOS SDK for building
- `ffmpeg` and `ffprobe` for merging media
- `aria2` for multi-connection downloads
- `node` for the current yt-dlp JavaScript challenge support

Install the optional runtime tools with Homebrew:

```sh
brew install ffmpeg aria2 node
```

## Quick start

Requirements: an Apple Silicon Mac, macOS 14 or later, and the Swift 6
Command Line Tools.

```sh
# 1. Install external runtime tools
brew install ffmpeg aria2 node

# 2. Enter the cloned repository
cd mediadock

# 3. Fetch the pinned official yt-dlp executable
./scripts/fetch-core.sh

# 4. Build and launch the local app
./scripts/build-app.sh
open build/MediaDock.app
```

For the complete Chinese walkthrough, see
[使用教程](docs/USAGE.zh-CN.md).

## Build from source

This repository publishes source code only. The build script creates an
ad-hoc signed local development app; the repository does not provide a
ready-to-use `.app`, `.dmg`, or binary release.

Download the pinned yt-dlp release from the official project:

```sh
./scripts/fetch-core.sh
```

Build the local app without a complete Xcode installation:

```sh
./scripts/build-app.sh
open build/MediaDock.app
```

The result is an ad-hoc signed local app at `build/MediaDock.app`. The script
also supports a full Xcode installation through `Package.swift`.

The build bundles only the pinned `yt-dlp` executable fetched by
`scripts/fetch-core.sh`. It intentionally does not copy or bundle FFmpeg,
ffprobe, aria2c, or Node.js, even if older local files remain in `Vendor/`.
These runtime tools are resolved from the user's PATH and common Homebrew or
user-local locations.

`yt-dlp_macos` is a PyInstaller standalone executable. Although the yt-dlp
source repository is Unlicense, the upstream project states that this combined
standalone executable is licensed under GPL-3.0-or-later. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for official source and
license links.

## Before downloading

- Use a direct page URL supported by yt-dlp. DRM-protected media, paid access,
  and human-verification challenges are not bypassed.
- High-quality videos are often delivered as separate video and audio streams.
  Install `ffmpeg` and `ffprobe` so MediaDock can merge them.
- `aria2` enables multi-connection downloads when the server supports byte
  ranges. Unsupported sources automatically fall back to the compatible
  downloader.
- `node` is recommended for sites that require yt-dlp's JavaScript challenge
  support.
- A download can require more time than parsing. Pause, resume, and retry are
  available from the queue and history views.

The detailed Chinese user guide covers single links, batches, queue controls,
history, browser login reuse, settings, and troubleshooting:

- [MediaDock 0.1.0 使用教程](docs/USAGE.zh-CN.md)

## Privacy

All parsing, Cookies, download history, and media stay on the local Mac.
MediaDock has no backend and does not upload account data.

When browser-login reuse is enabled, MediaDock copies a consistent snapshot of
the selected Chromium profile's Cookies database into its own Application
Support directory. This data is never committed to Git. macOS may ask the user
to authorize access to `Chrome Safe Storage` in Keychain the first time it is
read.

## Current limitations

- Apple Silicon only.
- Chrome and Edge are the currently supported browser-login sources.
- The app is ad-hoc signed and is not notarized for public binary distribution.
- Site support and extraction reliability depend on yt-dlp and current platform
  behavior.
- The source repository does not ship a ready-to-use `.dmg` or `.app` release.

## Third-party software

MediaDock calls third-party command-line tools as separate programs. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for licensing and attribution.
The source release does not redistribute third-party executables.
MediaDock is not affiliated with or endorsed by yt-dlp, FFmpeg, aria2, Google,
Apple, or any supported media platform.

## Security

Please read [SECURITY.md](SECURITY.md) before reporting a security issue. Never
post Cookies, passwords, verification codes, private URLs, or full diagnostic
archives in a public issue.

## License

MediaDock's original source code is licensed under the MIT License. See
[LICENSE](LICENSE). Third-party programs retain their own licenses.
