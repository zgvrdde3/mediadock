# Third-party notices

MediaDock calls the following projects as separate command-line programs.
Their licenses apply to those projects and their distributions. MediaDock's
original SwiftUI source code remains under the MIT License.

This repository is a source release. It does not contain third-party
executables or a ready-to-distribute application bundle.

## yt-dlp

- Project: <https://github.com/yt-dlp/yt-dlp>
- Pinned release: <https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.21>
- Standalone asset:
  <https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.21/yt-dlp_macos>
- SHA-256 of `yt-dlp_macos`:
  `7a6fe71d7d680f1fb0ac18d4949873d77db2859e90017c0f44bd94b23be4ee40`
- Corresponding source tag:
  <https://github.com/yt-dlp/yt-dlp/tree/2026.10.21>
- Release source archive:
  <https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.21/yt-dlp.tar.gz>
- PyInstaller third-party license manifest:
  <https://github.com/yt-dlp/yt-dlp/blob/6ccd977303412151ee23352c6257dd658ffc1987/THIRD_PARTY_LICENSES.txt>
- Standalone executable license: **GPL-3.0-or-later**
- Role: media extraction and download engine

The yt-dlp git repository and its PyPI source and wheel distributions are
licensed under the Unlicense. However, the upstream README states that
PyInstaller-bundled releases, including `yt-dlp_macos`, contain GPLv3+ licensed
code and that the combined executable is licensed under GPLv3+. The standalone
executable must therefore not be described as Unlicense-only.

`scripts/fetch-core.sh` downloads this pinned standalone executable into the
ignored `Vendor/` directory for local development. The executable is not
included in this source repository. A distributor that includes it in an
application package must comply with GPL-3.0-or-later, preserve the upstream
notices, and provide the complete corresponding source for the executable and
its bundled dependencies. The upstream source tag, source archive, build
metadata, and `THIRD_PARTY_LICENSES.txt` identify the corresponding source
components.

MediaDock is an unofficial frontend and does not claim endorsement by the
yt-dlp project.

## aria2

- Project: <https://github.com/aria2/aria2>
- License: GPL-2.0-or-later
- Role: optional multi-connection file downloader

This repository does not contain or package aria2. Users install it from
Homebrew and MediaDock launches `aria2c` as a separate command-line process.
The public build script intentionally ignores `Vendor/aria2c`.

If a future binary release includes aria2, its distributor must identify the
exact aria2 version and build, distribute the applicable GPL license and
notices, and provide the complete corresponding source. That source package
must include the exact upstream version, any modifications or patches, the
scripts and installation information needed to build and install that binary,
and the complete source for bundled dependencies required by GPL. A version
string alone is not sufficient to satisfy the corresponding-source obligation.

## FFmpeg

- Project: <https://ffmpeg.org/>
- Licenses: LGPL-2.1-or-later and GPL-2.0-or-later depending on build options
- Role: optional media merging and conversion

FFmpeg and ffprobe are not included in this source repository. Users must
install or provide builds that they are permitted to use. The public build
script intentionally ignores `Vendor/ffmpeg` and `Vendor/ffprobe`; Homebrew or
another independently installed build is resolved at runtime.

An FFmpeg build configured with `--enable-nonfree` cannot be redistributed. A
future public binary release must use a build whose provenance and complete
configuration are documented, confirm that every enabled component permits
redistribution, and include the required licenses, notices, and corresponding
source or source offer.

## Node.js

- Project: <https://nodejs.org/>
- License: MIT and third-party component licenses
- Role: optional JavaScript runtime used by yt-dlp for some sites

Node.js is not included in this source repository. It is installed and used as
an external runtime dependency.

## Platform services

MediaDock does not grant rights to third-party media. Users are responsible for
following applicable copyright law and each platform's terms of service.
