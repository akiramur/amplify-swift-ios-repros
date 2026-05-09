#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${1:?target dir required}"

mkdir -p "$TARGET_DIR"
rsync -a --delete \
  --exclude node_modules \
  --exclude .amplify \
  --exclude amplify_outputs.json \
  "$SOURCE_DIR"/ "$TARGET_DIR"/

echo "Copied repro project to $TARGET_DIR"
