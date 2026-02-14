#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
LOG_DIR="$ROOT_DIR/logs"
TMP_DIR="$ROOT_DIR/tmp"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

remove_path() {
  local p="$1"
  if [ -e "$p" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "[dry-run] remove $p"
    else
      rm -rf "$p"
      echo "removed $p"
    fi
  fi
}

echo "Pruning non-runtime files..."
remove_path "$LOG_DIR"
remove_path "$TMP_DIR"
remove_path "$DATA_DIR/dem"
remove_path "$DATA_DIR/osm"
remove_path "$DATA_DIR/sources"
remove_path "$DATA_DIR/tile_weights.tsv.gz"
remove_path "$DATA_DIR/tiles"
remove_path "$DATA_DIR/tmp"
remove_path "$DATA_DIR/.DS_Store"

mkdir -p "$LOG_DIR" "$TMP_DIR" "$DATA_DIR/mbtiles" "$DATA_DIR/pmtiles" "$DATA_DIR/styles"
find "$DATA_DIR" -name '.DS_Store' -type f -delete 2>/dev/null || true

echo "Done. Kept runtime essentials under:"
echo "  $DATA_DIR/config.json"
echo "  $DATA_DIR/styles/route-planner/style.json"
echo "  $DATA_DIR/mbtiles/*.mbtiles"
echo "  $DATA_DIR/pmtiles/*.pmtiles"
