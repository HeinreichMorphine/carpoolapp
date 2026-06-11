# OSRM Data Compilation Script for Windows PowerShell
# This script crops and compiles the Melaka roadmap extract.
# Make sure Docker Desktop is running before executing this script.

$ErrorActionPreference = "Stop"

Write-Host "--------------------------------------------------" -ForegroundColor Cyan
Write-Host "OSRM Router Compiler - Melaka-Only Extract" -ForegroundColor Cyan
Write-Host "--------------------------------------------------" -ForegroundColor Cyan

$rawFile = Join-Path $PSScriptRoot "malaysia-singapore-brunei-latest.osm.pbf"
$melakaPbf = Join-Path $PSScriptRoot "melaka-latest.osm.pbf"

# 1. Crop Melaka bounding box if not already cropped
if (-not (Test-Path $melakaPbf)) {
    if (-not (Test-Path $rawFile)) {
        Write-Error "Could not find raw OSM file: $rawFile"
        exit 1
    }
    Write-Host "[0/3] Cropping Melaka bounding box from Malaysia-Singapore-Brunei dataset..." -ForegroundColor Yellow
    docker run --rm -v "${PSScriptRoot}:/data" yagajs/osmosis osmosis --read-pbf /data/malaysia-singapore-brunei-latest.osm.pbf --bounding-box left=102.1 right=102.5 bottom=2.15 top=2.45 --write-pbf /data/melaka-latest.osm.pbf
} else {
    Write-Host "Found existing Melaka cropped dataset: $melakaPbf" -ForegroundColor Green
}

Write-Host "[1/3] Extracting road networks (using car profile)..." -ForegroundColor Yellow
docker run --rm -v "${PSScriptRoot}:/data" osrm/osrm-backend:latest osrm-extract -p /opt/car.lua /data/melaka-latest.osm.pbf

Write-Host "[2/3] Partitioning cells for multi-level Dijkstra..." -ForegroundColor Yellow
docker run --rm -v "${PSScriptRoot}:/data" osrm/osrm-backend:latest osrm-partition /data/melaka-latest.osm.pbf

Write-Host "[3/3] Customizing traffic and speed metrics..." -ForegroundColor Yellow
docker run --rm -v "${PSScriptRoot}:/data" osrm/osrm-backend:latest osrm-customize /data/melaka-latest.osm.pbf

Write-Host "--------------------------------------------------" -ForegroundColor Green
Write-Host "OSRM Compilation Complete! Ready to launch stack." -ForegroundColor Green
Write-Host "--------------------------------------------------" -ForegroundColor Green
