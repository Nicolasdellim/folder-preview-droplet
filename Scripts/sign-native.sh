#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp/}folderpreview-sign.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Folder Preview Droplet.app"
mkdir -p "$APP/Contents"
ditto --norsrc --noextattr "$1/Contents" "$APP/Contents"
xattr -cr "$APP"
chflags -R nohidden "$APP"
codesign --force --sign "${SIGN_IDENTITY:--}" --entitlements "$ROOT/Native/Extension.entitlements" "$APP/Contents/PlugIns/FolderPreviewExtension.appex"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
ditto --norsrc --noextattr "$APP" "$1"
