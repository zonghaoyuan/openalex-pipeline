#!/bin/bash
###############################################################################
# Dependency Installation Script
# Purpose: Install all required dependencies for OpenAlex pipeline
# Author: Senior Data Engineer
# Date: 2025-12-12
###############################################################################

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

log "Starting dependency installation..."

###############################################################################
# System Packages
###############################################################################

log "Updating package lists..."
sudo apt-get update -qq

log "Installing AWS CLI..."
if command -v aws &> /dev/null; then
    warn "AWS CLI already installed"
else
    sudo apt-get install -y awscli
    log "AWS CLI installed successfully"
fi

log "Installing Docker..."
if command -v docker &> /dev/null; then
    warn "Docker already installed"
else
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    log "Docker installed successfully"
    warn "You may need to log out and back in for Docker group membership to take effect"
fi

log "Installing docker-compose..."
if command -v docker-compose &> /dev/null; then
    warn "docker-compose already installed"
else
    sudo apt-get install -y docker-compose
    log "docker-compose installed successfully"
fi

log "Installing Python 3 and pip..."
sudo apt-get install -y python3 python3-pip

###############################################################################
# Python Packages
###############################################################################

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

log "Installing Python dependencies..."
pip3 install -r "${PROJECT_ROOT}/config/requirements.txt"

log "Verifying Python packages..."
python3 -c "import duckdb; print(f'DuckDB version: {duckdb.__version__}')"

###############################################################################
# Optional Tools
###############################################################################

log "Installing optional utilities..."
sudo apt-get install -y \
    sqlite3 \
    htop \
    wget \
    curl \
    jq

###############################################################################
# Summary
###############################################################################

log ""
log "============================================================"
log "Dependency installation complete!"
log "============================================================"
log ""
log "Installed components:"
log "  ✓ AWS CLI:         $(aws --version 2>&1 | head -1)"
log "  ✓ Docker:          $(docker --version)"
log "  ✓ docker-compose:  $(docker-compose --version)"
log "  ✓ Python:          $(python3 --version)"
log "  ✓ DuckDB:          $(python3 -c 'import duckdb; print(duckdb.__version__)')"
log ""
log "Next steps:"
log "  1. Run: ./setup_metabase.sh"
log "  2. Run: ./run_pipeline.sh"
log ""
log "If Docker was just installed, log out and back in, then check:"
log "  docker ps"
log ""

exit 0
