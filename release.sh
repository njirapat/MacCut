#!/bin/bash
# Build and package MacCut.app as dist/MacCut-<version>.zip for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")"

bash build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
mkdir -p dist
# --norsrc/--noextattr/--noqtn: no resource forks or extended attributes (no ._ files) in the zip
ditto -c -k --norsrc --noextattr --noqtn --keepParent build/MacCut.app "dist/MacCut-$VERSION.zip"
shasum -a 256 "dist/MacCut-$VERSION.zip"
echo "Packaged dist/MacCut-$VERSION.zip"
