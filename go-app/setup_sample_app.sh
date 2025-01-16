#!/bin/bash

set -ex

SERVER_PORT=8080
XRAY_SDK_REPO="github.com/aws/aws-xray-sdk-go"

# Prompt user for the X-Ray SDK commit hash
while [[ -z "$COMMIT_HASH" ]]; do
    read -p "Enter the commit hash for the AWS X-Ray Go SDK (cannot be empty): " COMMIT_HASH
done

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
