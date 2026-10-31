# Changelog

## 0.1.0

- Initial source release.
- Native SwiftUI download and parsing workflow.
- Single-link and batch parsing.
- Queue management with progress, pause, resume, cancellation, and retry.
- Optional Chrome and Edge login-state reuse.
- aria2 multi-connection downloads.
- Concurrent HLS/DASH fragment downloads.
- Parallel separate video/audio downloads with FFmpeg merging.
- Local-only storage and no backend account system.
- Corrected yt-dlp standalone executable licensing to GPL-3.0-or-later and
  documented official corresponding-source locations.
- Changed source builds to bundle only pinned yt-dlp and to use externally
  installed FFmpeg, ffprobe, aria2c, and Node.js.
- Hardened Git ignore rules for credentials, Cookies, media, archives, local
  binaries, and build artifacts.
