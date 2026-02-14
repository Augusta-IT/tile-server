#!/usr/bin/env bash
# Build terrain/contour MBTiles for route-planner style.
#
# Inputs:
# - data/dem/global-coarse/ETOPO1_Ice_c_geotiff.tif
# - data/dem/copernicus-30m-ca-uk/*.tif
#
# Outputs:
# - data/mbtiles/terrain_global_250m.mbtiles
# - data/mbtiles/contours_global_250m.mbtiles
# - data/mbtiles/terrain_ca_uk_hi.mbtiles
# - data/mbtiles/contours_ca_uk_hi.mbtiles
# - data/mbtiles/slope_ca_uk_hi.mbtiles

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEM_ROOT="${DEM_ROOT:-$ROOT_DIR/data/dem}"
MBTILES_DIR="${MBTILES_DIR:-$ROOT_DIR/data/mbtiles}"
TMP_DIR="${TMP_DIR:-$ROOT_DIR/tmp/build-terrain}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"

GLOBAL_DEM="${GLOBAL_DEM:-$DEM_ROOT/global-coarse/ETOPO1_Ice_c_geotiff.tif}"
FOCUS_GLOB="${FOCUS_GLOB:-$DEM_ROOT/copernicus-30m-ca-uk/*.tif}"

OUT_TERRAIN_GLOBAL="$MBTILES_DIR/terrain_global_250m.mbtiles"
OUT_CONTOURS_GLOBAL="$MBTILES_DIR/contours_global_250m.mbtiles"
OUT_TERRAIN_FOCUS="$MBTILES_DIR/terrain_ca_uk_hi.mbtiles"
OUT_CONTOURS_FOCUS="$MBTILES_DIR/contours_ca_uk_hi.mbtiles"
OUT_SLOPE_FOCUS="$MBTILES_DIR/slope_ca_uk_hi.mbtiles"

GLOBAL_CONTOUR_INTERVAL_M="${GLOBAL_CONTOUR_INTERVAL_M:-200}"
FOCUS_CONTOUR_INTERVAL_M="${FOCUS_CONTOUR_INTERVAL_M:-50}"
FORCE="${FORCE:-0}"

mkdir -p "$MBTILES_DIR" "$TMP_DIR" "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/build_terrain_mbtiles_${TS}.log"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for c in gdalbuildvrt gdalwarp gdaldem gdal_contour gdal_translate ogr2ogr; do
  need_cmd "$c"
done

if [ ! -s "$GLOBAL_DEM" ]; then
  echo "Missing global DEM: $GLOBAL_DEM" >&2
  exit 1
fi

if ! ls $FOCUS_GLOB >/dev/null 2>&1; then
  echo "No focus DEM tiles found for pattern: $FOCUS_GLOB" >&2
  exit 1
fi

build_focus_vrt() {
  local region="$1"
  local vrt="$2"
  local list_file="$TMP_DIR/${region}_tiles.txt"
  : > "$list_file"

  local file base coords lat lon
  for file in $FOCUS_GLOB; do
    [ -f "$file" ] || continue
    base="$(basename "$file")"
    coords="$(parse_tile_lat_lon "$base" || true)"
    [ -n "$coords" ] || continue
    lat="${coords%% *}"
    lon="${coords##* }"

    case "$region" in
      ca)
        if [ "$lat" -ge 32 ] && [ "$lat" -le 42 ] && [ "$lon" -ge -125 ] && [ "$lon" -le -114 ]; then
          echo "$file" >> "$list_file"
        fi
        ;;
      uk)
        if [ "$lat" -ge 49 ] && [ "$lat" -le 61 ] && [ "$lon" -ge -11 ] && [ "$lon" -le 3 ]; then
          echo "$file" >> "$list_file"
        fi
        ;;
      *)
        echo "Unknown region: $region" >&2
        exit 1
        ;;
    esac
  done

  if [ ! -s "$list_file" ]; then
    echo "No focus DEM files selected for region '$region'" >&2
    exit 1
  fi

  log "Building $region focus VRT from selected Copernicus 30m tiles..."
  gdalbuildvrt -input_file_list "$list_file" "$vrt" >>"$LOG_FILE" 2>&1
}

parse_tile_lat_lon() {
  # $1 basename tile; outputs "lat lon"
  local tile="$1"
  local ns lat_s ew lon_s lat lon

  if [[ "$tile" =~ _([NnSs])([0-9]{2})_00_([EeWw])([0-9]{3})_00_DEM(\.tif)?$ ]]; then
    ns="${BASH_REMATCH[1]}"
    lat_s="${BASH_REMATCH[2]}"
    ew="${BASH_REMATCH[3]}"
    lon_s="${BASH_REMATCH[4]}"
  elif [[ "$tile" =~ ^([NnSs])([0-9]{2})([EeWw])([0-9]{3})(\.tif)?$ ]]; then
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

build_global_hillshade_mbtiles() {
  if [ -s "$OUT_TERRAIN_GLOBAL" ] && [ "$FORCE" != "1" ]; then
    log "Skipping existing $OUT_TERRAIN_GLOBAL"
    return 0
  fi
  rm -f "$OUT_TERRAIN_GLOBAL"

  local hs_tif="$TMP_DIR/global_hillshade.tif"
  log "Building global hillshade raster..."
  gdaldem hillshade "$GLOBAL_DEM" "$hs_tif" -z 1.0 -s 111120 -compute_edges -multidirectional >>"$LOG_FILE" 2>&1

  log "Converting global hillshade to MBTiles..."
  gdal_translate -of MBTILES "$hs_tif" "$OUT_TERRAIN_GLOBAL" \
    -co TILE_FORMAT=PNG \
    -co ZOOM_LEVEL_STRATEGY=AUTO \
    >>"$LOG_FILE" 2>&1
}

build_global_contours_mbtiles() {
  if [ -s "$OUT_CONTOURS_GLOBAL" ] && [ "$FORCE" != "1" ]; then
    log "Skipping existing $OUT_CONTOURS_GLOBAL"
    return 0
  fi
  rm -f "$OUT_CONTOURS_GLOBAL"

  local contour_gpkg="$TMP_DIR/global_contours.gpkg"
  rm -f "$contour_gpkg"

  log "Extracting global contours every ${GLOBAL_CONTOUR_INTERVAL_M}m..."
  gdal_contour -a ele -i "$GLOBAL_CONTOUR_INTERVAL_M" "$GLOBAL_DEM" "$contour_gpkg" -f GPKG >>"$LOG_FILE" 2>&1

  log "Converting global contours to MBTiles (layer: contour)..."
  ogr2ogr -f MBTILES "$OUT_CONTOURS_GLOBAL" "$contour_gpkg" \
    -nln contour \
    -dsco MAXZOOM=8 \
    -dsco MINZOOM=0 \
    >>"$LOG_FILE" 2>&1
}

build_focus_hillshade_mbtiles() {
  if [ -s "$OUT_TERRAIN_FOCUS" ] && [ "$FORCE" != "1" ]; then
    log "Skipping existing $OUT_TERRAIN_FOCUS"
    return 0
  fi
  rm -f "$OUT_TERRAIN_FOCUS"

  local ca_vrt="$TMP_DIR/focus_ca_30m.vrt"
  local uk_vrt="$TMP_DIR/focus_uk_30m.vrt"
  local ca_hs="$TMP_DIR/focus_ca_hillshade.tif"
  local uk_hs="$TMP_DIR/focus_uk_hillshade.tif"
  local merged_hs_vrt="$TMP_DIR/focus_hillshade_merged.vrt"

  rm -f "$ca_hs" "$uk_hs" "$merged_hs_vrt"

  build_focus_vrt "ca" "$ca_vrt"
  build_focus_vrt "uk" "$uk_vrt"

  log "Building CA hillshade raster..."
  gdaldem hillshade "$ca_vrt" "$ca_hs" -z 1.0 -s 111120 -compute_edges -multidirectional >>"$LOG_FILE" 2>&1
  log "Building UK hillshade raster..."
  gdaldem hillshade "$uk_vrt" "$uk_hs" -z 1.0 -s 111120 -compute_edges -multidirectional >>"$LOG_FILE" 2>&1

  log "Merging CA+UK hillshade rasters..."
  gdalbuildvrt "$merged_hs_vrt" "$ca_hs" "$uk_hs" >>"$LOG_FILE" 2>&1

  log "Converting CA+UK hillshade to MBTiles..."
  gdal_translate -of MBTILES "$merged_hs_vrt" "$OUT_TERRAIN_FOCUS" \
    -co TILE_FORMAT=PNG \
    -co ZOOM_LEVEL_STRATEGY=AUTO \
    >>"$LOG_FILE" 2>&1
}

build_focus_contours_mbtiles() {
  if [ -s "$OUT_CONTOURS_FOCUS" ] && [ "$FORCE" != "1" ]; then
    log "Skipping existing $OUT_CONTOURS_FOCUS"
    return 0
  fi
  rm -f "$OUT_CONTOURS_FOCUS"

  local ca_vrt="$TMP_DIR/focus_ca_30m.vrt"
  local uk_vrt="$TMP_DIR/focus_uk_30m.vrt"
  local ca_gpkg="$TMP_DIR/focus_ca_contours.gpkg"
  local uk_gpkg="$TMP_DIR/focus_uk_contours.gpkg"
  local contour_gpkg="$TMP_DIR/focus_contours.gpkg"

  rm -f "$ca_gpkg" "$uk_gpkg" "$contour_gpkg"
  build_focus_vrt "ca" "$ca_vrt"
  build_focus_vrt "uk" "$uk_vrt"

  log "Extracting CA contours every ${FOCUS_CONTOUR_INTERVAL_M}m..."
  gdal_contour -a ele -i "$FOCUS_CONTOUR_INTERVAL_M" "$ca_vrt" "$ca_gpkg" -f GPKG >>"$LOG_FILE" 2>&1
  log "Extracting UK contours every ${FOCUS_CONTOUR_INTERVAL_M}m..."
  gdal_contour -a ele -i "$FOCUS_CONTOUR_INTERVAL_M" "$uk_vrt" "$uk_gpkg" -f GPKG >>"$LOG_FILE" 2>&1

  log "Merging CA+UK contour vectors..."
  ogr2ogr -f GPKG "$contour_gpkg" "$ca_gpkg" -nln contour >>"$LOG_FILE" 2>&1
  ogr2ogr -f GPKG "$contour_gpkg" "$uk_gpkg" -nln contour -append -update >>"$LOG_FILE" 2>&1

  log "Converting CA+UK contours to MBTiles (layer: contour)..."
  ogr2ogr -f MBTILES "$OUT_CONTOURS_FOCUS" "$contour_gpkg" \
    -nln contour \
    -dsco MAXZOOM=13 \
    -dsco MINZOOM=4 \
    >>"$LOG_FILE" 2>&1
}

build_focus_slope_mbtiles() {
  if [ -s "$OUT_SLOPE_FOCUS" ] && [ "$FORCE" != "1" ]; then
    log "Skipping existing $OUT_SLOPE_FOCUS"
    return 0
  fi
  rm -f "$OUT_SLOPE_FOCUS"

  local ca_vrt="$TMP_DIR/focus_ca_30m.vrt"
  local uk_vrt="$TMP_DIR/focus_uk_30m.vrt"
  local ca_slope="$TMP_DIR/focus_ca_slope_pct.tif"
  local uk_slope="$TMP_DIR/focus_uk_slope_pct.tif"
  local ca_slope_color="$TMP_DIR/focus_ca_slope_color.tif"
  local uk_slope_color="$TMP_DIR/focus_uk_slope_color.tif"
  local merged_slope_vrt="$TMP_DIR/focus_slope_merged.vrt"
  local color_file="$TMP_DIR/slope_color_ramp.txt"

  rm -f "$ca_slope" "$uk_slope" "$ca_slope_color" "$uk_slope_color" "$merged_slope_vrt" "$color_file"
  build_focus_vrt "ca" "$ca_vrt"
  build_focus_vrt "uk" "$uk_vrt"

  cat > "$color_file" <<'EOF'
0   245 244 238
5   229 218 196
10  214 190 156
20  189 153 111
30  164 123 85
45  132 90 59
60  103 65 43
80  74 44 30
100 56 32 22
EOF

  log "Building CA slope raster (percent)..."
  gdaldem slope "$ca_vrt" "$ca_slope" -p -compute_edges >>"$LOG_FILE" 2>&1
  log "Building UK slope raster (percent)..."
  gdaldem slope "$uk_vrt" "$uk_slope" -p -compute_edges >>"$LOG_FILE" 2>&1

  log "Applying slope color ramp (CA)..."
  gdaldem color-relief "$ca_slope" "$color_file" "$ca_slope_color" -alpha >>"$LOG_FILE" 2>&1
  log "Applying slope color ramp (UK)..."
  gdaldem color-relief "$uk_slope" "$color_file" "$uk_slope_color" -alpha >>"$LOG_FILE" 2>&1

  log "Merging CA+UK slope rasters..."
  gdalbuildvrt "$merged_slope_vrt" "$ca_slope_color" "$uk_slope_color" >>"$LOG_FILE" 2>&1

  log "Converting CA+UK slope to MBTiles..."
  gdal_translate -of MBTILES "$merged_slope_vrt" "$OUT_SLOPE_FOCUS" \
    -co TILE_FORMAT=PNG \
    -co ZOOM_LEVEL_STRATEGY=AUTO \
    >>"$LOG_FILE" 2>&1
}

log "Starting terrain MBTiles build."
log "Log file: $LOG_FILE"

build_global_hillshade_mbtiles
build_global_contours_mbtiles
build_focus_hillshade_mbtiles
build_focus_contours_mbtiles
build_focus_slope_mbtiles

log "Build complete."
log "Outputs:"
log " - $OUT_TERRAIN_GLOBAL"
log " - $OUT_CONTOURS_GLOBAL"
log " - $OUT_TERRAIN_FOCUS"
log " - $OUT_CONTOURS_FOCUS"
log " - $OUT_SLOPE_FOCUS"
