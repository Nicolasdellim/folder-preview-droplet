#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build-native.sh
swift package resolve
KIT="${DROPPYKIT_ROOT:-$PWD/.build/checkouts/droppykit}"
"$KIT/Scripts/build-droplet.sh" --arch universal
"$KIT/Scripts/validate-droplet.sh" --bundle "$PWD/.build/FolderPreviewDroplet.droplet" --no-submission
