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
if [[ "$signer" != "-" ]]; then
    share_team="$(codesign --display --verbose=4 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    if [[ "$share_team" =~ ^[A-Z0-9]{10}$ ]]; then
        share_group="$share_team.mastersync"
        share="$app/Contents/PlugIns/MasterSyncShare.appex"
        mkdir -p "$share/Contents/MacOS"
        install -m 644 "$repo/macOS/ShareExtension/Info.plist" "$share/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Add :MasterSyncShareGroup string $share_group" "$app/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Add :MasterSyncShareGroup string $share_group" "$share/Contents/Info.plist"
        xcrun swiftc -module-cache-path "$scratch/module-cache" -parse-as-library -application-extension \
            -target "$(uname -m)-apple-macos14" -framework Social -Xlinker -e -Xlinker _NSExtensionMain \
            "$repo/macOS/Sources/NexusCore/ShareInbox.swift" "$repo/macOS/ShareExtension/ShareController.swift" \
            -o "$share/Contents/MacOS/MasterSyncShare"
        cat > "$stage/app.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.application-groups</key><array><string>$share_group</string></array>
</dict></plist>
PLIST
        cat > "$stage/share.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.files.user-selected.read-only</key><true/>
<key>com.apple.security.application-groups</key><array><string>$share_group</string></array>
</dict></plist>
PLIST
        codesign --force --sign "$signer" --entitlements "$stage/share.entitlements" "$share"
        codesign --force --sign "$signer" --entitlements "$stage/app.entitlements" "$app"
    fi
fi
codesign --verify --deep --strict "$app"
archive="$stage/Nexus masterSync macOS.zip"
ditto -c -k --keepParent "$app" "$archive"
install -m 644 "$archive" "$dist/Nexus masterSync macOS.zip"
printf '%s\n' "$dist/Nexus masterSync macOS.zip"
if [[ "${NEXUS_BUILD_DMG:-1}" == "1" ]]; then
    bash "$repo/scripts/build-dmg.sh" "$app" "$dist/MasterSync-macOS.dmg"
fi
