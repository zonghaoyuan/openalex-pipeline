#!/bin/bash
###############################################################################
# Run ETL in Screen Session
# Purpose: Execute full ETL pipeline in detached screen session
###############################################################################

SCREEN_NAME="openalex-etl"
PROJECT_DIR="/home/ubuntu/openalex"

echo "Starting OpenAlex ETL in screen session..."
echo "Screen name: ${SCREEN_NAME}"
echo ""

# Check if screen is installed
if ! command -v screen &> /dev/null; then
    echo "Screen is not installed. Installing..."
    sudo apt-get update -qq && sudo apt-get install -y screen
fi

# Kill existing session if it exists
screen -S ${SCREEN_NAME} -X quit 2>/dev/null || true

# Create new detached screen session and run ETL
screen -dmS ${SCREEN_NAME} bash -c "cd ${PROJECT_DIR} && ./run.sh; exec bash"

echo "✓ ETL started in screen session!"
echo ""
echo "Useful commands:"
echo "  - Attach to session:    screen -r ${SCREEN_NAME}"
echo "  - Detach from session:  Ctrl+A then D"
echo "  - View logs:            tail -f ${PROJECT_DIR}/logs/etl_process.log"
echo "  - List sessions:        screen -ls"
echo "  - Kill session:         screen -S ${SCREEN_NAME} -X quit"
echo ""

