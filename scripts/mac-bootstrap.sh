#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/EduPanel.xcodeproj"
PLIST="$ROOT_DIR/EduPanel/Resources/GoogleService-Info.plist"
CONFIG="$ROOT_DIR/Config/Shared.xcconfig"

echo "Checking EduPanel iOS setup..."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: xcodebuild is not available. Install Xcode and open it once."
  exit 1
fi

if [ ! -d "$PROJECT" ]; then
  echo "ERROR: Missing project at $PROJECT"
  exit 1
fi

if [ ! -f "$PLIST" ]; then
  echo "ERROR: Missing GoogleService-Info.plist at EduPanel/Resources/"
  exit 1
fi

if grep -q "REPLACE_ME" "$CONFIG"; then
  echo "ERROR: Config/Shared.xcconfig still has REPLACE_ME values."
  exit 1
fi

echo "Xcode:"
xcodebuild -version

echo
echo "Schemes:"
xcodebuild -list -project "$PROJECT"

echo
echo "Setup looks ready."
