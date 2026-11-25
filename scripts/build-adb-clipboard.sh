#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
android_jar="$sdk/platforms/android-36/android.jar"
d8="$sdk/build-tools/36.0.0/d8"
output="${1:?Informe o caminho de saída para o JAR.}"
if [[ ! -f "$android_jar" || ! -x "$d8" ]]; then
    printf '%s\n' 'Defina ANDROID_HOME com o Android SDK Platform 36 e Build Tools 36.0.0.' >&2
    exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/nexus-adb-clipboard.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/classes" "$(dirname "$output")"
java_bin="${JAVA_HOME:+$JAVA_HOME/bin/}"
"${java_bin}javac" --release 11 -classpath "$android_jar" -d "$work/classes" \
    "$repo/android/adb-clipboard/NexusUsbClipboard.java"
"${java_bin}jar" --create --file "$work/classes.jar" -C "$work/classes" .
"$d8" --min-api 29 --lib "$android_jar" --output "$work/NexusUsbClipboard.jar" "$work/classes.jar"
install -m 644 "$work/NexusUsbClipboard.jar" "$output"
