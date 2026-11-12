#!/bin/sh
# Build the on-device helper (Apple Vision faces, AVFoundation video) into local-data/bin.
set -e
cd "$(dirname "$0")/.."
mkdir -p local-data/bin
swiftc -O -swift-version 5 tools/mac-helper/PhotoCuratorHelper.swift -o local-data/bin/pc-helper
echo "built local-data/bin/pc-helper"
