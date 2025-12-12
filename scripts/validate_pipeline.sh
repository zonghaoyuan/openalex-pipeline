#!/bin/bash
###############################################################################
# Pipeline Validation Script
# Purpose: Verify pipeline setup and data integrity
# Author: Senior Data Engineer
# Date: 2025-12-12
###############################################################################

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN++))
}

section() {
    echo ""
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}$(printf '=%.0s' {1..60})${NC}"
}

section "VALIDATING PIPELINE SETUP"

###############################################################################
# Check Scripts
###############################################################################
section "Script Files"

if [ -x "${SCRIPT_DIR}/sync_openalex.sh" ]; then
    check_pass "sync_openalex.sh exists and is executable"
else
    check_fail "sync_openalex.sh missing or not executable"
fi

if [ -x "${SCRIPT_DIR}/process_data.py" ]; then
    check_pass "process_data.py exists and is executable"
else
    check_fail "process_data.py missing or not executable"
fi

if [ -x "${SCRIPT_DIR}/run_pipeline.sh" ]; then
    check_pass "run_pipeline.sh exists and is executable"
else
    check_fail "run_pipeline.sh missing or not executable"
fi

if [ -f "${PROJECT_ROOT}/config/init_duckdb.sql" ]; then
    check_pass "init_duckdb.sql exists"
else
    check_fail "init_duckdb.sql missing"
fi

if [ -f "${PROJECT_ROOT}/config/docker-compose.yml" ]; then
    check_pass "docker-compose.yml exists"
else
    check_fail "docker-compose.yml missing"
fi

###############################################################################
# Check Dependencies
###############################################################################
section "System Dependencies"

if command -v python3 &> /dev/null; then
    VERSION=$(python3 --version)
    check_pass "Python 3 installed: $VERSION"
else
    check_fail "Python 3 not found"
fi

if command -v aws &> /dev/null; then
    VERSION=$(aws --version 2>&1 | head -1)
    check_pass "AWS CLI installed: $VERSION"
else
    check_warn "AWS CLI not found (S3 sync will not work)"
fi

if command -v docker &> /dev/null; then
    VERSION=$(docker --version)
    check_pass "Docker installed: $VERSION"
else
    check_fail "Docker not found"
fi

if command -v docker-compose &> /dev/null; then
    VERSION=$(docker-compose --version)
    check_pass "docker-compose installed: $VERSION"
else
    check_fail "docker-compose not found"
fi

if command -v sqlite3 &> /dev/null; then
    check_pass "SQLite3 installed"
else
    check_warn "SQLite3 not found (optional but recommended)"
fi

###############################################################################
# Check Python Packages
###############################################################################
section "Python Packages"

if python3 -c "import duckdb" 2>/dev/null; then
    VERSION=$(python3 -c "import duckdb; print(duckdb.__version__)")
    check_pass "DuckDB installed: $VERSION"
else
    check_fail "DuckDB Python package not found"
fi

if python3 -c "import pandas" 2>/dev/null; then
    check_pass "Pandas installed (optional)"
else
    check_warn "Pandas not installed (optional but recommended)"
fi

###############################################################################
# Check Directories
###############################################################################
section "Directory Structure"

if [ -d "${PROJECT_ROOT}/data/source" ]; then
    SIZE=$(du -sh "${PROJECT_ROOT}/data/source" 2>/dev/null | cut -f1)
    COUNT=$(find "${PROJECT_ROOT}/data/source" -name "*.gz" -type f 2>/dev/null | wc -l)
    check_pass "Source data directory exists: $SIZE, $COUNT files"
else
    check_warn "Source data directory not found (will be created on first sync)"
fi

if [ -d "${PROJECT_ROOT}/data/parquet" ]; then
    SIZE=$(du -sh "${PROJECT_ROOT}/data/parquet" 2>/dev/null | cut -f1)
    COUNT=$(find "${PROJECT_ROOT}/data/parquet" -name "*.parquet" -type f 2>/dev/null | wc -l)
    check_pass "Parquet directory exists: $SIZE, $COUNT files"
else
    check_warn "Parquet directory not found (will be created on first ETL run)"
fi

if [ -d "${PROJECT_ROOT}/logs" ]; then
    check_pass "Logs directory exists"
else
    check_warn "Logs directory not found (will be created automatically)"
fi

if [ -d "${PROJECT_ROOT}/metabase/plugins" ]; then
    if [ -f "${PROJECT_ROOT}/metabase/plugins/duckdb.metabase-driver.jar" ]; then
        check_pass "DuckDB Metabase plugin installed"
    else
        check_warn "DuckDB plugin not found (run ./scripts/setup_metabase.sh)"
    fi
else
    check_warn "Metabase plugins directory not found (run ./scripts/setup_metabase.sh)"
fi

###############################################################################
# Check State Database
###############################################################################
section "State Management"

if [ -f "${PROJECT_ROOT}/state/etl_state.db" ]; then
    PROCESSED=$(sqlite3 "${PROJECT_ROOT}/state/etl_state.db" "SELECT COUNT(*) FROM processed_files" 2>/dev/null || echo "0")
    FAILED=$(sqlite3 "${PROJECT_ROOT}/state/etl_state.db" "SELECT COUNT(*) FROM failed_files" 2>/dev/null || echo "0")
    check_pass "State database exists: $PROCESSED processed, $FAILED failed"
else
    check_warn "State database not found (will be created on first ETL run)"
fi

###############################################################################
# Check Docker
###############################################################################
section "Docker Services"

if docker ps &> /dev/null; then
    if docker ps | grep -q "openalex-metabase"; then
        STATUS=$(docker inspect openalex-metabase --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
        check_pass "Metabase container running: $STATUS"
    else
        check_warn "Metabase container not running (start with: docker-compose up -d)"
    fi
else
    check_warn "Cannot access Docker daemon (may need sudo or group membership)"
fi

###############################################################################
# Check Disk Space
###############################################################################
section "System Resources"

AVAILABLE=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$AVAILABLE" -gt 100 ]; then
    check_pass "Disk space available: ${AVAILABLE}GB"
elif [ "$AVAILABLE" -gt 50 ]; then
    check_warn "Disk space low: ${AVAILABLE}GB (recommend 100GB+ free)"
else
    check_fail "Disk space critically low: ${AVAILABLE}GB"
fi

TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -gt 30 ]; then
    check_pass "RAM available: ${TOTAL_RAM}GB"
else
    check_warn "RAM may be insufficient: ${TOTAL_RAM}GB (recommend 32GB+)"
fi

###############################################################################
# Data Integrity Checks
###############################################################################
section "Data Integrity"

if [ -d "${PROJECT_ROOT}/data/parquet" ] && [ "$(find "${PROJECT_ROOT}/data/parquet" -name "*.parquet" -type f | wc -l)" -gt 0 ]; then
    echo "Testing Parquet file integrity..."

    # Test reading a sample Parquet file
    SAMPLE_FILE=$(find "${PROJECT_ROOT}/data/parquet" -name "*.parquet" -type f | head -1)
    if [ -n "$SAMPLE_FILE" ]; then
        if python3 -c "import duckdb; con = duckdb.connect(':memory:'); con.execute('SELECT COUNT(*) FROM read_parquet(\"$SAMPLE_FILE\")').fetchone()" 2>/dev/null; then
            check_pass "Parquet files readable by DuckDB"
        else
            check_fail "Cannot read Parquet file: $SAMPLE_FILE"
        fi
    fi
else
    check_warn "No Parquet files to validate yet"
fi

###############################################################################
# Summary
###############################################################################
section "VALIDATION SUMMARY"

echo ""
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${YELLOW}${WARN} warnings${NC}, ${RED}${FAIL} failed${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
    if [ $WARN -eq 0 ]; then
        echo -e "${GREEN}✓ Pipeline is fully configured and ready to run!${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Run: cd ${PROJECT_ROOT} && ./scripts/run_pipeline.sh"
        echo "  2. Access Metabase: http://localhost:3000"
    else
        echo -e "${YELLOW}⚠ Pipeline is mostly ready, but has some warnings${NC}"
        echo ""
        echo "Recommended actions:"
        echo "  - Review warnings above"
        echo "  - Run ./scripts/install_dependencies.sh if dependencies are missing"
        echo "  - Run ./scripts/setup_metabase.sh to setup Metabase"
    fi
else
    echo -e "${RED}✗ Pipeline has critical issues that need to be fixed${NC}"
    echo ""
    echo "Required actions:"
    echo "  1. Fix failed checks above"
    echo "  2. Run ./scripts/install_dependencies.sh to install missing dependencies"
    echo "  3. Re-run this validation script"
    exit 1
fi

echo ""
exit 0
