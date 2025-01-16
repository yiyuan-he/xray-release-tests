#!/bin/bash

set -ex

# Define variables
XRAY_SDK_REPO="github.com/aws/aws-xray-sdk-node"

# Prompt user for the X-Ray SDK commit hash
while [[ -z "$COMMIT_HASH" ]]; do 
    read -p "Enter the commit hash for the AWS X-Ray Node SDK (cannot be empty): " COMMIT_HASH
done

# Use the AWS X-Ray SDK on the specified commit hash
echo "Cloning the AWS X-Ray SDK repo locally..."
git clone https://$XRAY_SDK_REPO || { echo "Failed to clone the AWS X-Ray SDK repo"; exit 1; }

cd aws-xray-sdk-node
if [ "$COMMIT_HASH" != "latest" ]; then
    echo "Checking out commit hash: $COMMIT_HASH"
    git checkout $COMMIT_HASH || { echo "Failed to checkout commit hash"; exit 1; }
fi

echo "Installing dependencies..."
npm install

# Link the SDK to the server
echo "Linking the AWS X-Ray SDK to the server project..."
cd ..
npm install ./aws-xray-sdk-node

# Start the server
echo "Starting the server..."
node app.js
