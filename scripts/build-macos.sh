#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="${NEXUS_BUILD_DIR:-$repo/macOS/.build}"
configuration="${NEXUS_CONFIGURATION:-release}"
dist="${NEXUS_DIST_DIR:-$repo/dist}"
signer="${NEXUS_SIGN_IDENTITY:--}"
mkdir -p "$scratch/module-cache" "$scratch/cache" "$dist"
export CLANG_MODULE_CACHE_PATH="$scratch/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$scratch/module-cache"

swift_args=(--package-path "$repo/macOS" --scratch-path "$scratch" --cache-path "$scratch/cache" --disable-sandbox -c "$configuration")
swift build "${swift_args[@]}"
bin="$(swift build "${swift_args[@]}" --show-bin-path)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/nexus-macos.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Nexus masterSync.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$bin/NexusMasterSync" "$app/Contents/MacOS/NexusMasterSync"
install -m 644 "$repo/macOS/Info.plist" "$app/Contents/Info.plist"
install -m 644 "$repo/macOS/Resources/Nexus.icns" "$app/Contents/Resources/Nexus.icns"
bash "$repo/scripts/build-adb-clipboard.sh" "$app/Contents/Resources/NexusUsbClipboard.jar"
codesign --force --sign "$signer" "$app"
codesign --verify --strict "$app"
archive="$stage/Nexus masterSync macOS.zip"
ditto -c -k --keepParent "$app" "$archive"
install -m 644 "$archive" "$dist/Nexus masterSync macOS.zip"
printf '%s\n' "$dist/Nexus masterSync macOS.zip"
