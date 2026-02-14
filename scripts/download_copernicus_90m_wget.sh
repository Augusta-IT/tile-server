#!/usr/bin/env bash
# scripts/download_copernicus_90m_wget.sh
set -u

DEST_DIR="${1:-./data/dem/copernicus-90m}"
WORK_DIR="${2:-./tmp/copernicus-90m}"
LOG_DIR="${3:-./logs}"
LIST_URL="https://copernicus-dem-90m.s3.amazonaws.com/tileList.txt"
SLEEP_BETWEEN_PASSES="${SLEEP_BETWEEN_PASSES:-30}"

mkdir -p "$DEST_DIR" "$WORK_DIR" "$LOG_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/copernicus_90m_wget_${TS}.log"
ALL_TILES="$WORK_DIR/all_tiles.txt"
PENDING="$WORK_DIR/pending_tiles.txt"
FAILED="$WORK_DIR/failed_tiles.txt"

echo "[$(date)] Downloading tile list..." | tee -a "$LOG_FILE"
curl -fsSL "$LIST_URL" | tr -d '\r' > "$ALL_TILES"

# Keep only non-empty lines
awk 'NF' "$ALL_TILES" > "$PENDING"

pass=0
while [ -s "$PENDING" ]; do
  pass=$((pass + 1))
  : > "$FAILED"
  total=$(wc -l < "$PENDING" | tr -d ' ')
  echo "[$(date)] Pass $pass starting, pending tiles: $total" | tee -a "$LOG_FILE"

  while IFS= read -r tile; do
    [ -z "$tile" ] && continue
    out="$DEST_DIR/${tile}.tif"

    if [ -s "$out" ]; then
      echo "[$(date)] SKIP exists: $tile" >> "$LOG_FILE"
      continue
    fi

    url="https://copernicus-dem-90m.s3.amazonaws.com/${tile}/${tile}.tif"
    echo "[$(date)] GET $tile" | tee -a "$LOG_FILE"

    if wget -c \
      --retry-connrefused \
      --waitretry=5 \
      --read-timeout=60 \
      --timeout=60 \
      --tries=20 \
      -O "$out.part" "$url" >> "$LOG_FILE" 2>&1; then
      mv "$out.part" "$out"
    else
      rm -f "$out.part"
      echo "$tile" >> "$FAILED"
      echo "[$(date)] FAIL $tile (will retry in next pass)" | tee -a "$LOG_FILE"
    fi
  done < "$PENDING"

  if [ -s "$FAILED" ]; then
    mv "$FAILED" "$PENDING"
    left=$(wc -l < "$PENDING" | tr -d ' ')
    echo "[$(date)] Pass $pass done. Remaining: $left. Sleeping ${SLEEP_BETWEEN_PASSES}s..." | tee -a "$LOG_FILE"
    sleep "$SLEEP_BETWEEN_PASSES"
  else
    rm -f "$PENDING"
  fi
done

echo "[$(date)] Completed all Copernicus 90m tile downloads." | tee -a "$LOG_FILE"
