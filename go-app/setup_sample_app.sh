#!/bin/bash

set -ex

SERVER_PORT=8080
XRAY_SDK_REPO="github.com/aws/aws-xray-sdk-go"

# Prompt user for the commit hash or default to "latest"
read -p "Enter the commit hash (or branch) of the AWS X-Ray Go SDK [default=master]: " COMMIT_HASH
if [ -z "$COMMIT_HASH" ]; then
    COMMIT_HASH="latest"
    echo "Using the latest commit of the AWS X-Ray SDK."
else
    echo "Using commit hash: $COMMIT_HASH"
fi

# Update the AWS X-Ray SDK to the specified commit hash
echo "Updating AWS X-Ray SDK to commit: $COMMIT_HASH..."
go get $XRAY_SDK_REPO@$COMMIT_HASH || { echo "Falied to update the AWS X-Ray SDK"; exit 1; }
go mod tidy

# Build the Go server
echo "Building the server..."
go build -o server main.go || { echo "Failed to build the server"; exit 1; }

# Start the server
echo "Starting the server..."
./server
echo "Server started."
