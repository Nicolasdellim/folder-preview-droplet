#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/.build/native"
APP="$OUT/Folder Preview Droplet.app"
EXT="$APP/Contents/PlugIns/FolderPreviewExtension.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"
SDK="$(xcrun --show-sdk-path)"
SHARED=(Native/Model.swift Native/Archives.swift Native/Thumbnails.swift Native/GridItem.swift Native/PreviewController.swift)
APP_SLICES=(); EXT_SLICES=()
for arch in ${PREVIEW_ARCHS:-arm64 x86_64}; do
  xcrun swiftc -swift-version 5 -parse-as-library -O -target "$arch-apple-macos14.0" -sdk "$SDK" -I Native/CArchive -module-name FolderPreviewCompanion "${SHARED[@]}" Native/Companion.swift Native/Verify.swift -o "$OUT/companion-$arch" -framework AppKit -framework Quartz -framework ImageIO -framework QuickLookThumbnailing -framework CoreServices -larchive.2
  xcrun swiftc -swift-version 5 -parse-as-library -application-extension -O -target "$arch-apple-macos14.0" -sdk "$SDK" -I Native/CArchive -module-name FolderPreviewExtension "${SHARED[@]}" -o "$OUT/extension-$arch" -framework AppKit -framework Quartz -framework ImageIO -framework QuickLookThumbnailing -framework CoreServices -larchive.2 -Xlinker -e -Xlinker _NSExtensionMain
  APP_SLICES+=("$OUT/companion-$arch"); EXT_SLICES+=("$OUT/extension-$arch")
done
lipo -create "${APP_SLICES[@]}" -output "$APP/Contents/MacOS/FolderPreviewCompanion"
lipo -create "${EXT_SLICES[@]}" -output "$EXT/Contents/MacOS/FolderPreviewExtension"
python3 Scripts/make-plists.py "$APP"
python3 Scripts/make-fixtures.py Demo
cp -R Demo "$APP/Contents/Resources/"
if [ -f Assets/FolderPreviewDroplet.icns ]; then cp Assets/FolderPreviewDroplet.icns "$APP/Contents/Resources/"; fi
./Scripts/sign-native.sh "$APP"
mkdir -p Assets/Companion
rm -rf "Assets/Companion/Folder Preview Droplet.app"
ditto --norsrc --noextattr "$APP" "Assets/Companion/Folder Preview Droplet.app"
echo "Built $APP"
