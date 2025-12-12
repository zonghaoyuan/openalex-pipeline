#!/bin/bash
###############################################################################
# OpenAlex S3 Sync Script
# Purpose: Incrementally sync new/changed files from s3://openalex to local
# Author: Senior Data Engineer
# Date: 2025-12-12
###############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

S3_BUCKET="s3://openalex/data"
LOCAL_DIR="${PROJECT_ROOT}/data/source"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/sync_$(date +%Y%m%d_%H%M%S).log"
STATS_FILE="${PROJECT_ROOT}/logs/sync_stats.json"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

###############################################################################
# Functions
###############################################################################

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "${LOG_FILE}"
}

###############################################################################
# Pre-flight Checks
###############################################################################

log "Starting OpenAlex S3 Sync..."

# Create directories if they don't exist
mkdir -p "${LOCAL_DIR}"
mkdir -p "${LOG_DIR}"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
    error "Install with: sudo apt-get install awscli -y"
    exit 1
fi

log "Pre-flight checks passed."

###############################################################################
# S3 Sync Operation
###############################################################################

log "Syncing from ${S3_BUCKET} to ${LOCAL_DIR}"
log "Excluding: *legacy* patterns and metadata files"

# Capture start time
START_TIME=$(date +%s)

# Create temporary file to capture sync output
SYNC_OUTPUT=$(mktemp)

# Perform the sync with appropriate filters
# --no-sign-request: Access public bucket without credentials
# --exclude: Skip legacy data
# --delete: Remove local files that don't exist in S3 (keeps local in sync with remote)
aws s3 sync \
    "${S3_BUCKET}" \
    "${LOCAL_DIR}" \
    --no-sign-request \
    --delete \
    --exclude "*legacy*" \
    --exclude "*.html" \
    --exclude "*.txt" \
    2>&1 | tee -a "${LOG_FILE}" | tee "${SYNC_OUTPUT}"

SYNC_EXIT_CODE=${PIPESTATUS[0]}

# Count downloaded/updated files from sync output
# aws s3 sync outputs lines like: "download: s3://... to ..."
CHANGED_FILES=$(grep -c "^download:" "${SYNC_OUTPUT}" 2>/dev/null || echo "0")

# Capture end time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

###############################################################################
# Post-Sync Summary
###############################################################################

if [ ${SYNC_EXIT_CODE} -eq 0 ]; then
    log "Sync completed successfully in ${DURATION} seconds."
    log "Changed files: ${CHANGED_FILES}"

    # Count files
    TOTAL_GZ_FILES=$(find "${LOCAL_DIR}" -name "*.gz" -type f 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh "${LOCAL_DIR}" 2>/dev/null | cut -f1)
    TOTAL_SIZE_MB=$(du -sm "${LOCAL_DIR}" 2>/dev/null | cut -f1)

    log "Summary:"
    log "  - Total .gz files: ${TOTAL_GZ_FILES}"
    log "  - Total size: ${TOTAL_SIZE}"
    log "  - Log file: ${LOG_FILE}"

    # List entity types
    log "Entity types found:"
    ls -1 "${LOCAL_DIR}" 2>/dev/null | while read entity; do
        count=$(find "${LOCAL_DIR}/${entity}" -name "*.gz" -type f 2>/dev/null | wc -l)
        log "  - ${entity}: ${count} files"
    done

    # Write statistics to JSON file
    cat > "${STATS_FILE}" <<EOF
{
  "success": true,
  "sync_files": ${CHANGED_FILES},
  "sync_size_mb": ${TOTAL_SIZE_MB},
  "sync_duration_seconds": ${DURATION},
  "total_files": ${TOTAL_GZ_FILES},
  "total_size": "${TOTAL_SIZE}",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF

    # Clean up temporary file
    rm -f "${SYNC_OUTPUT}"

    exit 0
else
    error "Sync failed with exit code ${SYNC_EXIT_CODE}"
    error "Check log file: ${LOG_FILE}"

    # Write failure statistics
    cat > "${STATS_FILE}" <<EOF
{
  "success": false,
  "error_code": ${SYNC_EXIT_CODE},
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF

    rm -f "${SYNC_OUTPUT}"
    exit ${SYNC_EXIT_CODE}
fi
