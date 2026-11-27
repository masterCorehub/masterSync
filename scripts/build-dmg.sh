#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:?Informe o caminho para o .app (ex: dist/Nexus masterSync.app).}"
output="${2:-$repo/dist/MasterSync-macOS.dmg}"

if [[ ! -d "$app" || "${app##*.}" != "app" ]]; then
    printf 'Bundle .app inválido: %s\n' "$app" >&2
    exit 1
fi

stage="$(mktemp -d "${TMPDIR:-/tmp}/nexus-dmg.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT

app_name="$(basename "$app")"
ditto "$app" "$stage/$app_name"
ln -s /Applications "$stage/Applications"

tmp_dmg="$stage/MasterSync-macOS.dmg"
hdiutil create -volname "MasterSync" -srcfolder "$stage" -ov -format UDZO "$tmp_dmg" >/dev/null

mkdir -p "$(dirname "$output")"
install -m 644 "$tmp_dmg" "$output"
printf '%s\n' "$output"
