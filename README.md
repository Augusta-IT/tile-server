# tile-server

Offline-first local tile server stack for detailed map data.

This project runs:
- `tileserver-gl` for MBTiles with built-in web map and style endpoints
- `go-pmtiles` for direct PMTiles serving (optional)

## Data Layout

Place your tiles in these folders:

- MBTiles overlays for terrain style: `data/mbtiles/*.mbtiles`
- PMTiles basemap: `data/pmtiles/*.pmtiles`

Example:

```text
data/
  mbtiles/
    terrain_global_250m.mbtiles
    contours_global_250m.mbtiles
    terrain_ca_uk_hi.mbtiles
    contours_ca_uk_hi.mbtiles
    slope_ca_uk_hi.mbtiles
    ca_hi.mbtiles
  pmtiles/
    planet.pmtiles
```

## Quick Start

1. Create folders (if they do not exist):

```bash
mkdir -p data/mbtiles data/pmtiles
```

2. Copy env defaults:

```bash
cp .env.example .env
```

3. Start services:

```bash
docker compose up -d --force-recreate
```

4. Open the route-planning map UI:

`http://localhost:8080/styles/route-planner/`

5. Verify PMTiles API:

```bash
curl -I http://localhost:8081/planet.json
```

## DEM Source Download

Use the combined wget script to fetch source DEM data (excluding `planet.pmtiles`):

```bash
./scripts/download_dem_sources_wget.sh
```

Modes:

```bash
# Coarse global fallback source (single ETOPO1 package)
./scripts/download_dem_sources_wget.sh --global-only
# High-detail source for California + UK (Copernicus 30m)
./scripts/download_dem_sources_wget.sh --focus-only
```

## Services

- MBTiles server + map UI: `http://localhost:${TILESERVER_PORT:-8080}`
- PMTiles API: `http://localhost:${PMTILES_PORT:-8081}`

## Build MBTiles

Generate terrain MBTiles layers used by the route-planner style:

```bash
./scripts/build_terrain_mbtiles.sh
```

Monitor progress:

```bash
tail -f logs/build_terrain_mbtiles_*.log
```

Build California high-detail vector tiles (z15) for extra feature detail:

```bash
./scripts/build_ca_hi_vector_mbtiles.sh
```

This produces:

`data/mbtiles/ca_hi.mbtiles`

## Notes

- The style at `data/styles/route-planner/style.json` expects:
  - PMTiles source at `http://<tile-host>:8081/planet.json`
  - Global fallback raster terrain at `data/mbtiles/terrain_global_250m.mbtiles`
  - Global fallback vector contours at `data/mbtiles/contours_global_250m.mbtiles`
  - High-resolution California + UK raster terrain at `data/mbtiles/terrain_ca_uk_hi.mbtiles`
  - High-resolution California + UK vector contours at `data/mbtiles/contours_ca_uk_hi.mbtiles`
  - High-resolution California + UK slope raster at `data/mbtiles/slope_ca_uk_hi.mbtiles`
  - California high-zoom vector basemap at `data/mbtiles/ca_hi.mbtiles`
- Use one style URL with no switching. High-resolution CA/UK layers draw where tiles exist; global fallback fills everywhere else.
- If contour layer names are not `contour`, edit `source-layer` for `contours_global` and `contours_ca_uk_hi` in `data/styles/route-planner/style.json`.
- `ca_hi.mbtiles` is expected to use OpenMapTiles-style layers (`transportation`, `building`, `place`).

For remote clients (Overseer on another machine):
- `:8080` paths in style are host-agnostic (relative URLs).
- Set PMTiles basemap host with:

```bash
./scripts/set_style_remote_host.sh <tile_host_or_ip>
```

Then restart:

```bash
docker compose up -d --force-recreate
```

## Runtime Data Cleanup and Portability

Prune build-only data and keep runtime essentials:

```bash
./scripts/prune_runtime_data.sh
```

Dry-run mode:

```bash
./scripts/prune_runtime_data.sh --dry-run
```

Create a portable runtime bundle (MBTiles + PMTiles + style + config):

```bash
./scripts/export_runtime_bundle.sh
```

Import that bundle on another machine into a target folder:

```bash
./scripts/import_runtime_bundle.sh /path/to/tile-server-runtime-data_YYYYMMDD_HHMMSS.tar.gz /path/to/project
```

## Rebuild Data From Sources

Use one command to recreate MBTiles from raw sources on a new machine:

```bash
./scripts/rebuild_data_from_sources.sh
```

Important:
- This script rebuilds DEM + vector MBTiles.
- It does **not** download `planet.pmtiles`.
- Copy `planet.pmtiles` manually to `data/pmtiles/planet.pmtiles`, or pass:

```bash
./scripts/rebuild_data_from_sources.sh --planet-pmtiles /path/to/planet.pmtiles
```

Useful flags:

```bash
# only download source inputs
./scripts/rebuild_data_from_sources.sh --download-only

# only build from already-downloaded source inputs
./scripts/rebuild_data_from_sources.sh --build-only

# skip CA vector layer build
./scripts/rebuild_data_from_sources.sh --skip-ca-vector

# force rebuild outputs
./scripts/rebuild_data_from_sources.sh --force
```

Data size note:
- Runtime data in this project is roughly 130GB+ (`planet.pmtiles` dominates).
- Do not commit this data to GitHub; use local storage/object storage and scripts.
