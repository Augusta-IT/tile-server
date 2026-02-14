#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <bundle.tar.gz> [target_dir]" >&2
  exit 1
fi

BUNDLE="$1"
TARGET_DIR="${2:-$(pwd)}"

mkdir -p "$TARGET_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -xzf "$BUNDLE" -C "$TMP_DIR"
EXTRACTED_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

if [ -z "$EXTRACTED_DIR" ] || [ ! -f "$EXTRACTED_DIR/checksums.sha256" ]; then
  echo "Invalid bundle structure" >&2
  exit 1
fi

(
  cd "$EXTRACTED_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c checksums.sha256
  else
    shasum -a 256 -c checksums.sha256
  fi
)

mkdir -p "$TARGET_DIR/data/mbtiles" "$TARGET_DIR/data/pmtiles" "$TARGET_DIR/data/styles/route-planner"
cp "$EXTRACTED_DIR/data/config.json" "$TARGET_DIR/data/config.json"
cp "$EXTRACTED_DIR/data/styles/route-planner/style.json" "$TARGET_DIR/data/styles/route-planner/style.json"
cp "$EXTRACTED_DIR/docker-compose.yml" "$TARGET_DIR/docker-compose.yml"
cp -a "$EXTRACTED_DIR/data/mbtiles/." "$TARGET_DIR/data/mbtiles/"
cp -a "$EXTRACTED_DIR/data/pmtiles/." "$TARGET_DIR/data/pmtiles/"

echo "Imported runtime bundle into: $TARGET_DIR"
