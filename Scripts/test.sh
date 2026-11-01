#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp/}folderpreview-tests.XXXXXX")"
trap 'rm -rf "$FIXTURES"' EXIT
python3 Scripts/make-fixtures.py "$FIXTURES" --tests
xcrun swiftc -swift-version 5 -parse-as-library -I Native/CArchive Native/Model.swift Native/Archives.swift Tests/CoreTests.swift -larchive.2 -o .build/tests/core-tests
chflags -R nohidden "$FIXTURES"
.build/tests/core-tests "$FIXTURES" "$PWD/Tests/Fixtures"
