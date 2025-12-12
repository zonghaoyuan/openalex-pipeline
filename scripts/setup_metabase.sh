#!/bin/bash
###############################################################################
# Metabase Setup Script
# Purpose: Download DuckDB plugin and setup Metabase
# Author: Senior Data Engineer
# Date: 2025-12-12
###############################################################################

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

###############################################################################
# Pre-flight checks
###############################################################################

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

log "Starting Metabase setup..."
log "Project root: ${PROJECT_ROOT}"

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    error "docker-compose is not installed. Please install docker-compose first."
    exit 1
fi

###############################################################################
# Create directories
###############################################################################

log "Creating necessary directories..."
mkdir -p "${PROJECT_ROOT}/metabase/plugins"
mkdir -p "${PROJECT_ROOT}/data/parquet"

###############################################################################
# Download DuckDB plugin
###############################################################################

PLUGIN_DIR="${PROJECT_ROOT}/metabase/plugins"
PLUGIN_FILE="${PLUGIN_DIR}/duckdb.metabase-driver.jar"
PLUGIN_URL="https://github.com/AlexR2D2/metabase_duckdb_driver/releases/download/0.2.8/duckdb.metabase-driver.jar"

if [ -f "${PLUGIN_FILE}" ]; then
    warn "DuckDB plugin already exists at ${PLUGIN_FILE}"
    read -p "Do you want to re-download it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping plugin download."
    else
        log "Downloading DuckDB plugin for Metabase..."
        wget -q --show-progress "${PLUGIN_URL}" -O "${PLUGIN_FILE}"
        log "DuckDB plugin downloaded successfully."
    fi
else
    log "Downloading DuckDB plugin for Metabase..."
    wget -q --show-progress "${PLUGIN_URL}" -O "${PLUGIN_FILE}"
    log "DuckDB plugin downloaded successfully."
fi

###############################################################################
# Check if Parquet data exists
###############################################################################

PARQUET_COUNT=$(find "${PROJECT_ROOT}/data/parquet" -name "*.parquet" -type f 2>/dev/null | wc -l)

if [ "${PARQUET_COUNT}" -eq 0 ]; then
    warn "No Parquet files found in ./openalex_parquet"
    warn "You should run process_data.py first to convert data."
    info "You can still start Metabase now and add data later."
else
    log "Found ${PARQUET_COUNT} Parquet files ready to serve."
fi

###############################################################################
# Start Metabase
###############################################################################

log "Starting Metabase with docker-compose..."
cd "${PROJECT_ROOT}/config"
docker-compose up -d
cd "${SCRIPT_DIR}"

# Wait for Metabase to be ready
log "Waiting for Metabase to start (this may take 30-60 seconds)..."
sleep 10

# Check if container is running
if docker ps | grep -q "openalex-metabase"; then
    log "Metabase is running!"

    # Wait for health check
    for i in {1..30}; do
        if docker inspect openalex-metabase | grep -q '"Status": "healthy"'; then
            log "Metabase is healthy and ready!"
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""

    info ""
    info "============================================================"
    info "Metabase Setup Complete!"
    info "============================================================"
    info ""
    info "1. Access Metabase at: http://localhost:3000"
    info ""
    info "2. On first visit, create an admin account"
    info ""
    info "3. Add DuckDB Database:"
    info "   - Go to: Admin (gear icon) > Databases > Add database"
    info "   - Database type: DuckDB"
    info "   - Display name: OpenAlex"
    info "   - Connection string: md:/data (for MotherDuck) or leave empty for in-memory"
    info ""
    info "4. Run initialization SQL:"
    info "   - Copy contents of init_duckdb.sql"
    info "   - Run in Metabase SQL editor to create views"
    info ""
    info "5. Useful commands:"
    info "   - View logs:    docker-compose logs -f metabase"
    info "   - Stop:         docker-compose down"
    info "   - Restart:      docker-compose restart"
    info ""
    info "============================================================"
else
    error "Metabase container failed to start!"
    error "Check logs with: docker-compose logs metabase"
    exit 1
fi

###############################################################################
# Show DuckDB connection info
###############################################################################

echo ""
info "DuckDB Connection Instructions:"
echo ""
cat << 'EOF'
When configuring DuckDB in Metabase, you have two options:

Option 1: In-Memory Database (Fast, but recreates on restart)
  - Database: :memory:
  - After connecting, run init_duckdb.sql to create views

Option 2: Persistent Database File (Slower, but persists)
  - Database: /data/openalex.duckdb
  - Run init_duckdb.sql once, and views persist

For most analytics use cases, Option 1 (in-memory) is recommended
because Parquet files are already your persistent storage.

Example initialization (copy to Metabase SQL editor):
  CREATE VIEW works AS
  SELECT * FROM read_parquet('/data/works/**/*.parquet', union_by_name=true);

EOF

exit 0
