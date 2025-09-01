#!/usr/bin/bash

# =============================================================================
# MountAllS3 Test Script
# =============================================================================
#
# Simple test script that cleans up previous configurations and runs setup
# Used for development and testing purposes only

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "❌ Error: Could not load common.sh library"
    exit 1
}

rm -rf ~/.config/mountalls3
rm -rf ~/s3
rm -rf ~/.config/autostart/mountalls3.desktop
rm -rf ~/.local/bin/mountalls3

./setup-mountalls3.sh --debug-level 3
