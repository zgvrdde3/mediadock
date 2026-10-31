# Media core

`scripts/fetch-core.sh` downloads a pinned yt-dlp macOS binary into this folder.
The binary is excluded from Git and is not part of the source release.

FFmpeg, ffprobe, aria2c, and Node.js are optional runtime dependencies. Install
them with Homebrew:

```sh
brew install ffmpeg aria2 node
```

The public build script bundles only `Vendor/yt-dlp`. It intentionally ignores
`Vendor/ffmpeg`, `Vendor/ffprobe`, and `Vendor/aria2c`, even when those files
exist locally. FFmpeg, ffprobe, aria2c, and Node.js are resolved at runtime from
the user's PATH or common Homebrew and user-local locations.

License files kept in this directory are reference notices. They do not grant
permission to redistribute a locally built third-party executable. Review
`THIRD_PARTY_NOTICES.md` before packaging any additional binary.

Upstream projects:

- <https://github.com/yt-dlp/yt-dlp>
- <https://ffmpeg.org/>
- <https://github.com/aria2/aria2>
- <https://nodejs.org/>

See `THIRD_PARTY_NOTICES.md` in the repository root for licensing details.
