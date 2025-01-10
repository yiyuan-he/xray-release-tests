#!/bin/bash

# Location of X-Ray release testing resources
XRAY_DAEMON_DIR="$HOME/xray-release-testing"

echo "Starting cleanup..."

rm -rf $XRAY_DAEMON_DIR

echo "Cleanup complete."
