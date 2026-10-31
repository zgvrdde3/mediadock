#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
vendor="$project_root/Vendor"
yt_dlp_version="2026.10.21"
yt_dlp_sha256="7a6fe71d7d680f1fb0ac18d4949873d77db2859e90017c0f44bd94b23be4ee40"
yt_dlp_url="https://github.com/yt-dlp/yt-dlp/releases/download/${yt_dlp_version}/yt-dlp_macos"

mkdir -p "$vendor"

if [[ -x "$vendor/yt-dlp" ]] \
    && [[ "$(shasum -a 256 "$vendor/yt-dlp" | awk '{print $1}')" == "$yt_dlp_sha256" ]]; then
    echo "yt-dlp ${yt_dlp_version}: ready"
else
    temporary_binary="$(mktemp "${TMPDIR:-/tmp}/mediadock-yt-dlp.XXXXXX")"
    trap 'rm -f "$temporary_binary"' EXIT

    curl -L --fail --show-error "$yt_dlp_url" -o "$temporary_binary"
    actual_sha256="$(shasum -a 256 "$temporary_binary" | awk '{print $1}')"
    if [[ "$actual_sha256" != "$yt_dlp_sha256" ]]; then
        echo "yt-dlp checksum mismatch" >&2
        exit 1
    fi

    chmod 755 "$temporary_binary"
    mv "$temporary_binary" "$vendor/yt-dlp"
    trap - EXIT
    echo "yt-dlp ${yt_dlp_version}: downloaded"
fi

for dependency in ffmpeg ffprobe aria2c node; do
    if command -v "$dependency" >/dev/null 2>&1; then
        echo "$dependency: $(command -v "$dependency")"
    else
        echo "warning: $dependency was not found in PATH" >&2
    fi
done

echo "Install optional media tools with: brew install ffmpeg aria2 node"
