#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
build_root="$project_root/build"
app_path="$build_root/MediaDock.app"
contents="$app_path/Contents"
macos="$contents/MacOS"
resources="$contents/Resources"
core="$resources/MediaCore"

if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
else
    sdk="$(xcrun --sdk macosx --show-sdk-path)"
fi

export CLANG_MODULE_CACHE_PATH="$project_root/.build/clang-cache"
export SWIFT_MODULECACHE_PATH="$project_root/.build/swift-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULECACHE_PATH"

rm -rf "$app_path"
mkdir -p "$macos" "$resources" "$core"

typeset -a sources
sources=("${(@f)$(find "$project_root/Sources/MediaDock" -type f -name '*.swift' -print | LC_ALL=C sort)}")

swiftc \
    -parse-as-library \
    -O \
    -whole-module-optimization \
    -module-name MediaDock \
    -sdk "$sdk" \
    -target arm64-apple-macosx14.0 \
    -module-cache-path "$SWIFT_MODULECACHE_PATH" \
    "${sources[@]}" \
    -o "$macos/MediaDock"

cp "$project_root/Resources/Info.plist" "$contents/Info.plist"

python3 "$project_root/scripts/generate_icon.py" "$build_root/AppIcon.icns"
cp "$build_root/AppIcon.icns" "$resources/AppIcon.icns"

# Source releases bundle only the pinned yt-dlp executable fetched by
# scripts/fetch-core.sh. FFmpeg, ffprobe, aria2c, and Node.js must remain
# user-installed runtime dependencies so their build provenance and licenses
# can be reviewed independently.
if [[ -x "$project_root/Vendor/yt-dlp" ]]; then
    cp "$project_root/Vendor/yt-dlp" "$core/yt-dlp"
    chmod 755 "$core/yt-dlp"
else
    echo "warning: Vendor/yt-dlp is missing; run scripts/fetch-core.sh" >&2
fi

for binary in ffmpeg ffprobe aria2c; do
    if [[ -e "$project_root/Vendor/$binary" ]]; then
        echo "warning: ignoring Vendor/$binary; using the user-installed runtime dependency" >&2
    fi
done

cp "$project_root/THIRD_PARTY_NOTICES.md" "$resources/THIRD_PARTY_NOTICES.md"
cp "$project_root/LICENSE" "$resources/LICENSE"

if [[ -f "$core/yt-dlp" ]]; then
    codesign --force --sign - "$core/yt-dlp"
fi

codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"

echo "$app_path"
