#!/usr/bin/env bash
# Download raw DEM source data for:
# - Global fallback source (single coarse global DEM package)
# - High-detail focus areas (Copernicus 30m for California + UK)
#
# Output folders:
#   data/dem/global-coarse/
#   data/dem/copernicus-30m-ca-uk/

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEM_ROOT="${DEM_ROOT:-$ROOT_DIR/data/dem}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
TMP_DIR="${TMP_DIR:-$ROOT_DIR/tmp/dem-download}"

GLOBAL_COARSE_DIR="$DEM_ROOT/global-coarse"
COP30_FOCUS_DIR="$DEM_ROOT/copernicus-30m-ca-uk"

COP30_TILELIST_URL="https://copernicus-dem-30m.s3.amazonaws.com/tileList.txt"
ETOPO1_ZIP_URL="https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO1/data/ice_surface/cell_registered/georeferenced_tiff/ETOPO1_Ice_c_geotiff.zip"

SLEEP_BETWEEN_PASSES="${SLEEP_BETWEEN_PASSES:-30}"
WGET_TRIES="${WGET_TRIES:-20}"
WGET_TIMEOUT="${WGET_TIMEOUT:-60}"

RUN_GLOBAL=1
RUN_FOCUS=1

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--global-only] [--focus-only]

Options:
  --global-only   Download only coarse global fallback source (single ETOPO1 package).
  --focus-only    Download only Copernicus 30m DEM for California + UK.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --global-only)
      RUN_GLOBAL=1
      RUN_FOCUS=0
      ;;
    --focus-only)
      RUN_GLOBAL=0
      RUN_FOCUS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

mkdir -p "$GLOBAL_COARSE_DIR" "$COP30_FOCUS_DIR" "$LOG_DIR" "$TMP_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/dem_download_${TS}.log"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd wget
need_cmd curl
need_cmd awk
need_cmd tr

download_with_wget() {
  # $1=url $2=output
  local url="$1"
  local out="$2"
  local tmp="${out}.part"

  if [ -s "$out" ]; then
    return 0
  fi

  if wget -c \
    --retry-connrefused \
    --waitretry=5 \
    --read-timeout="$WGET_TIMEOUT" \
    --timeout="$WGET_TIMEOUT" \
    --tries="$WGET_TRIES" \
    -O "$tmp" "$url" >>"$LOG_FILE" 2>&1; then
    mv "$tmp" "$out"
    return 0
  fi

  rm -f "$tmp"
  return 1
}

download_from_tile_list() {
  # $1=tile_list_url, $2=bucket_base_url, $3=dest_dir, $4=selected_tiles_file
  local tile_list_url="$1"
  local bucket_base="$2"
  local dest_dir="$3"
  local selected_file="$4"
  local pending="${selected_file}.pending"
  local failed="${selected_file}.failed"

  awk 'NF' "$selected_file" > "$pending"
  local pass=0
  while [ -s "$pending" ]; do
    pass=$((pass + 1))
    : > "$failed"
    local total
    total=$(wc -l < "$pending" | tr -d ' ')
    log "Pass $pass for $(basename "$dest_dir"): pending $total"

    while IFS= read -r tile; do
      [ -z "$tile" ] && continue
      local out="$dest_dir/${tile}.tif"
      local url="${bucket_base}/${tile}/${tile}.tif"

      if [ -s "$out" ]; then
        continue
      fi

      if ! download_with_wget "$url" "$out"; then
        echo "$tile" >> "$failed"
        log "Tile failed (will retry): $tile"
      fi
    done < "$pending"

    if [ -s "$failed" ]; then
      mv "$failed" "$pending"
      local left
      left=$(wc -l < "$pending" | tr -d ' ')
      log "Pass $pass done; remaining $left; sleeping ${SLEEP_BETWEEN_PASSES}s."
      sleep "$SLEEP_BETWEEN_PASSES"
    else
      rm -f "$pending"
    fi
  done

  log "Completed download for $(basename "$dest_dir")."
}

download_global_coarse() {
  local zip_path="$GLOBAL_COARSE_DIR/ETOPO1_Ice_c_geotiff.zip"
  local tif_path="$GLOBAL_COARSE_DIR/ETOPO1_Ice_c.tif"

  need_cmd unzip

  if [ ! -s "$zip_path" ]; then
    log "Downloading coarse global DEM package (ETOPO1)..."
    download_with_wget "$ETOPO1_ZIP_URL" "$zip_path" || return 1
  else
    log "Coarse global package already downloaded: $zip_path"
  fi

  if [ ! -s "$tif_path" ]; then
    log "Extracting coarse global DEM GeoTIFF..."
    unzip -o "$zip_path" -d "$GLOBAL_COARSE_DIR" >>"$LOG_FILE" 2>&1 || return 1
  else
    log "Coarse global GeoTIFF already present: $tif_path"
  fi

  log "Coarse global DEM source ready."
}

parse_tile_lat_lon() {
  # $1=tile -> outputs "lat lon" on stdout, returns non-zero on parse failure
  local tile="$1"
  local ns lat_s ew lon_s lat lon

  if [[ "$tile" =~ ^([NnSs])([0-9]{2})([EeWw])([0-9]{3})$ ]]; then
    ns="${BASH_REMATCH[1]}"
    lat_s="${BASH_REMATCH[2]}"
    ew="${BASH_REMATCH[3]}"
    lon_s="${BASH_REMATCH[4]}"
  elif [[ "$tile" =~ _([NnSs])([0-9]{2})_00_([EeWw])([0-9]{3})_00_DEM$ ]]; then
    ns="${BASH_REMATCH[1]}"
    lat_s="${BASH_REMATCH[2]}"
    ew="${BASH_REMATCH[3]}"
    lon_s="${BASH_REMATCH[4]}"
  else
    return 1
  fi

  lat=$((10#$lat_s))
  lon=$((10#$lon_s))
  case "$ns" in
    S|s) lat=$((-lat)) ;;
  esac
  case "$ew" in
    W|w) lon=$((-lon)) ;;
  esac

  printf '%s %s\n' "$lat" "$lon"
}

is_focus_tile() {
  # supported tile name formats:
  # - N37W122
  # - Copernicus_DSM_COG_10_N37_00_W122_00_DEM
  local tile="$1"
  local coords lat lon
  coords="$(parse_tile_lat_lon "$tile")" || return 1
  lat="${coords%% *}"
  lon="${coords##* }"

  # California box: lat 32..42, lon -125..-114
  if [ "$lat" -ge 32 ] && [ "$lat" -le 42 ] && [ "$lon" -ge -125 ] && [ "$lon" -le -114 ]; then
    return 0
  fi

  # UK box: lat 49..61, lon -11..3
  if [ "$lat" -ge 49 ] && [ "$lat" -le 61 ] && [ "$lon" -ge -11 ] && [ "$lon" -le 3 ]; then
    return 0
  fi

  return 1
}


download_cop30_focus() {
  local all_tiles="$TMP_DIR/cop30_all_tiles.txt"
  local selected="$TMP_DIR/cop30_focus_selected.txt"
  local bucket="https://copernicus-dem-30m.s3.amazonaws.com"

  log "Fetching Copernicus 30m tile list..."
  curl -fsSL "$COP30_TILELIST_URL" | tr -d '\r' > "$all_tiles"
  : > "$selected"

  while IFS= read -r raw; do
    local tile
    tile="$raw"
    [ -z "$tile" ] && continue
    if is_focus_tile "$tile"; then
      echo "$tile" >> "$selected"
    fi
  done < "$all_tiles"

  sort -u "$selected" -o "$selected"
  local count
  count=$(wc -l < "$selected" | tr -d ' ')
  log "Selected Copernicus 30m focus tiles (CA+UK): $count"

  download_from_tile_list "$COP30_TILELIST_URL" "$bucket" "$COP30_FOCUS_DIR" "$selected"
}

log "Starting DEM download job."
log "DEM root: $DEM_ROOT"
log "Log file: $LOG_FILE"

if [ "$RUN_GLOBAL" -eq 1 ]; then
  download_global_coarse || log "Coarse global source step ended with errors."
fi

if [ "$RUN_FOCUS" -eq 1 ]; then
  download_cop30_focus || log "Copernicus 30m focus step ended with errors."
fi

log "All selected download steps finished."
