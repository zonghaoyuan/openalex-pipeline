#!/bin/bash
###############################################################################
# OpenAlex Pipeline - Quick Launch Script
# Purpose: Convenient wrapper to run the main pipeline
# Author: Senior Data Engineer
# Date: 2025-12-12
###############################################################################

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Execute the main pipeline script
exec "${SCRIPT_DIR}/scripts/run_pipeline.sh" "$@"
