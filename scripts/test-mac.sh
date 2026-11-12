#!/bin/sh
# Unit tests of the native app's core (models, API client, library logic, strings).
# Uses the Xcode 27 toolchain without changing the system's xcode-select.
set -e
cd "$(dirname "$0")/../mac"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
exec swift test "$@"
