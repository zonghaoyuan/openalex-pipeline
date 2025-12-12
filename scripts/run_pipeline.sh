#!/bin/bash
###############################################################################
# OpenAlex Data Pipeline - Master Orchestrator
# Purpose: Run the complete pipeline: Sync → ETL → Report
# Author: Senior Data Engineer
# Date: 2025-12-12
###############################################################################

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

###############################################################################
# Configuration
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
LOG_DIR="${PROJECT_ROOT}/logs"
PIPELINE_LOG="${LOG_DIR}/pipeline_$(date +%Y%m%d_%H%M%S).log"

# Pipeline component scripts
SYNC_SCRIPT="${SCRIPT_DIR}/sync_openalex.sh"
ETL_SCRIPT="${SCRIPT_DIR}/process_data.py"
EMAIL_SCRIPT="${SCRIPT_DIR}/send_email_notification.sh"

# Data directories
SOURCE_DIR="${PROJECT_ROOT}/data/source"
PARQUET_DIR="${PROJECT_ROOT}/data/parquet"
STATE_DB="${PROJECT_ROOT}/state/etl_state.db"

# Create logs directory
mkdir -p "${LOG_DIR}"

###############################################################################
# Logging Functions
###############################################################################

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${PIPELINE_LOG}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "${PIPELINE_LOG}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "${PIPELINE_LOG}"
}

section() {
    echo -e "\n${BOLD}${BLUE}$1${NC}" | tee -a "${PIPELINE_LOG}"
    echo -e "${BLUE}$(printf '=%.0s' {1..80})${NC}" | tee -a "${PIPELINE_LOG}"
}

###############################################################################
# Pre-flight Checks
###############################################################################

preflight_checks() {
    section "PRE-FLIGHT CHECKS"

    # Check if sync script exists
    if [ ! -f "${SYNC_SCRIPT}" ]; then
        error "Sync script not found: ${SYNC_SCRIPT}"
        exit 1
    fi

    # Check if ETL script exists
    if [ ! -f "${ETL_SCRIPT}" ]; then
        error "ETL script not found: ${ETL_SCRIPT}"
        exit 1
    fi

    # Check if Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed"
        exit 1
    fi

    # Check if required Python packages are installed
    python3 -c "import duckdb" 2>/dev/null || {
        error "DuckDB Python package not found. Install with: pip3 install duckdb"
        exit 1
    }

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        warn "AWS CLI not found. Sync step will be skipped."
        warn "Install with: sudo apt-get install awscli -y"
        SKIP_SYNC=true
    else
        SKIP_SYNC=false
    fi

    log "All pre-flight checks passed!"
}

###############################################################################
# Phase 1: S3 Sync
###############################################################################

run_sync() {
    section "PHASE 1: S3 SYNC"

    if [ "${SKIP_SYNC}" = true ]; then
        warn "Skipping sync phase (AWS CLI not available)"
        return 0
    fi

    log "Starting S3 sync..."
    SYNC_START=$(date +%s)

    if bash "${SYNC_SCRIPT}"; then
        SYNC_END=$(date +%s)
        SYNC_DURATION=$((SYNC_END - SYNC_START))
        log "✓ Sync completed successfully in ${SYNC_DURATION} seconds"
        return 0
    else
        error "✗ Sync failed!"
        return 1
    fi
}

###############################################################################
# Phase 2: ETL Processing
###############################################################################

run_etl() {
    section "PHASE 2: ETL PROCESSING"

    log "Starting ETL conversion..."
    ETL_START=$(date +%s)

    if python3 "${ETL_SCRIPT}"; then
        ETL_END=$(date +%s)
        ETL_DURATION=$((ETL_END - ETL_START))
        log "✓ ETL completed successfully in ${ETL_DURATION} seconds"
        return 0
    else
        error "✗ ETL failed!"
        return 1
    fi
}

###############################################################################
# Phase 3: Generate Report
###############################################################################

generate_report() {
    section "PIPELINE SUMMARY REPORT"

    # Calculate total duration
    PIPELINE_END=$(date +%s)
    TOTAL_DURATION=$((PIPELINE_END - PIPELINE_START))

    # Count files
    SOURCE_FILES=$(find "${SOURCE_DIR}" -name "*.gz" -type f 2>/dev/null | wc -l)
    PARQUET_FILES=$(find "${PARQUET_DIR}" -name "*.parquet" -type f 2>/dev/null | wc -l)

    # Calculate sizes
    SOURCE_SIZE=$(du -sh "${SOURCE_DIR}" 2>/dev/null | cut -f1 || echo "N/A")
    PARQUET_SIZE=$(du -sh "${PARQUET_DIR}" 2>/dev/null | cut -f1 || echo "N/A")

    # Display report
    log ""
    log "Pipeline execution completed at: $(date)"
    log "Total duration: ${TOTAL_DURATION} seconds ($(($TOTAL_DURATION / 60)) minutes)"
    log ""
    log "Data Summary:"
    log "  Source Files (.gz):     ${SOURCE_FILES}"
    log "  Source Size:            ${SOURCE_SIZE}"
    log "  Parquet Files:          ${PARQUET_FILES}"
    log "  Parquet Size:           ${PARQUET_SIZE}"
    log ""
    log "Storage Locations:"
    log "  Source Data:            ${SOURCE_DIR}"
    log "  Parquet Data:           ${PARQUET_DIR}"
    log "  State Database:         ${STATE_DB}"
    log ""
    log "Log Files:"
    log "  Pipeline Log:           ${PIPELINE_LOG}"
    log "  ETL Process Log:        ${LOG_DIR}/etl_process.log"
    log "  ETL Error Log:          ${LOG_DIR}/etl_errors.log"
    log ""

    # Entity-level breakdown
    log "Entity Breakdown:"
    for entity in authors concepts domains fields funders institutions publishers sources subfields topics works; do
        entity_dir="${PARQUET_DIR}/${entity}"
        if [ -d "${entity_dir}" ]; then
            count=$(find "${entity_dir}" -name "*.parquet" -type f 2>/dev/null | wc -l)
            size=$(du -sh "${entity_dir}" 2>/dev/null | cut -f1)
            log "  ${entity}: ${count} files (${size})"
        fi
    done

    log ""
    log "Next Steps:"
    log "  1. Verify data: SELECT * FROM read_parquet('${PARQUET_DIR}/works/**/*.parquet') LIMIT 10;"
    log "  2. Access Metabase: http://localhost:3000"
    log "  3. Run init_duckdb.sql in Metabase to create views"
    log ""
}

###############################################################################
# Error Handler
###############################################################################

cleanup() {
    if [ $? -ne 0 ]; then
        error "Pipeline failed! Check logs for details."
        error "Pipeline log: ${PIPELINE_LOG}"
        exit 1
    fi
}

trap cleanup EXIT

###############################################################################
# Main Pipeline Execution
###############################################################################

main() {
    section "OPENALEX DATA PIPELINE - STARTING"
    log "Pipeline started at: $(date)"
    log "Working directory: $(pwd)"
    log "Log file: ${PIPELINE_LOG}"

    PIPELINE_START=$(date +%s)

    # Run pipeline phases
    preflight_checks

    # Phase 1: Sync (optional, skipped if no AWS CLI)
    SHOULD_SEND_EMAIL=false
    if [ "${SKIP_SYNC:-false}" = false ]; then
        run_sync || exit 1

        # Check if any files were changed during sync
        SYNC_STATS_FILE="${LOG_DIR}/sync_stats.json"
        if [ -f "${SYNC_STATS_FILE}" ]; then
            CHANGED_FILES=$(jq -r '.sync_files // 0' "${SYNC_STATS_FILE}" 2>/dev/null || echo "0")

            if [ "$CHANGED_FILES" -eq 0 ]; then
                log "No files changed. Skipping ETL and email notification."
                section "PIPELINE COMPLETED - NO UPDATES"
                exit 0
            else
                log "Detected ${CHANGED_FILES} changed files. Proceeding with ETL."
                SHOULD_SEND_EMAIL=true
            fi
        else
            warn "Sync stats file not found. Proceeding with ETL anyway."
            SHOULD_SEND_EMAIL=true
        fi
    fi

    # Phase 2: ETL (required)
    ETL_SUCCESS=false
    if run_etl; then
        ETL_SUCCESS=true
    fi

    # Generate final report
    generate_report

    # Phase 3: Send email notification (only if files changed)
    if [ "$SHOULD_SEND_EMAIL" = true ]; then
        section "SENDING EMAIL NOTIFICATION"

        # Merge sync and ETL stats
        ETL_STATS_FILE="${LOG_DIR}/etl_stats.json"
        COMBINED_STATS_FILE="${LOG_DIR}/combined_stats.json"

        if [ -f "${SYNC_STATS_FILE}" ] && [ -f "${ETL_STATS_FILE}" ]; then
            # Combine both JSON files
            jq -s '.[0] * .[1]' "${SYNC_STATS_FILE}" "${ETL_STATS_FILE}" > "${COMBINED_STATS_FILE}" 2>/dev/null || {
                log "Warning: Failed to combine stats files. Using ETL stats only."
                cp "${ETL_STATS_FILE}" "${COMBINED_STATS_FILE}"
            }
        elif [ -f "${ETL_STATS_FILE}" ]; then
            cp "${ETL_STATS_FILE}" "${COMBINED_STATS_FILE}"
        else
            log "Warning: No stats files found."
            echo '{}' > "${COMBINED_STATS_FILE}"
        fi

        # Send email based on ETL result
        if [ "$ETL_SUCCESS" = true ]; then
            log "Sending success notification email..."
            bash "${EMAIL_SCRIPT}" success "${COMBINED_STATS_FILE}" || warn "Failed to send email notification"
        else
            log "Sending failure notification email..."
            bash "${EMAIL_SCRIPT}" failure "${COMBINED_STATS_FILE}" || warn "Failed to send email notification"
        fi
    fi

    if [ "$ETL_SUCCESS" = true ]; then
        section "PIPELINE COMPLETED SUCCESSFULLY"
        log "All phases completed successfully!"
        exit 0
    else
        error "Pipeline failed during ETL phase!"
        exit 1
    fi
}

###############################################################################
# Script Entry Point
###############################################################################

# Check for help flag
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

OpenAlex Data Pipeline - Master Orchestrator

This script runs the complete data pipeline:
  1. Sync new data from S3 (if AWS CLI available)
  2. Convert new JSONL files to Parquet (incremental)
  3. Generate summary report

OPTIONS:
  -h, --help     Show this help message

EXAMPLES:
  # Run the full pipeline
  ./run_pipeline.sh

  # Run with output to both console and log file (default)
  ./run_pipeline.sh

  # Add to crontab for weekly execution (Sunday at 2 AM)
  0 2 * * 0 cd /home/ubuntu && ./run_pipeline.sh >> ./logs/cron.log 2>&1

LOGS:
  Pipeline logs are saved to: ./logs/pipeline_YYYYMMDD_HHMMSS.log
  ETL logs are saved to: ./logs/etl_process.log
  Errors are logged to: ./logs/etl_errors.log

For more information, see README.md
EOF
    exit 0
fi

# Run the pipeline
main "$@"
