#!/bin/bash

set -ex

# Define variables
PROJECT_DIR=$(pwd)
XRAY_SDK_REPO="github.com/aws/aws-xray-sdk-dotnet"

# Prompt user for the X-Ray SDK commit hash
while [[ -z "$COMMIT_HASH" ]]; do
    read -p "Enter the commit hash for the AWS X-Ray .NET SDK (cannot be empty): " COMMIT_HASH
done

# Use the AWS X-Ray SDK on the specified commit hash
echo "Cloning the AWS X-Ray SDK repo locally...:"
git clone https://$XRAY_SDK_REPO $HOME/xray-release-testing/aws-xray-sdk-dotnet || { echo "Failed to clone the AWS X-Ray SDK repo"; exit 1; }
cd $HOME/xray-release-testing/aws-xray-sdk-dotnet
if [ "$COMMIT_HASH" != "latest" ]; then
    echo "Checking out commit hash: $COMMIT_HASH"
    git checkout $COMMIT_HASH || { echo "Failed to checkout commit hash"; exit 1; }
fi
cd $PROJECT_DIR
dotnet add reference $HOME/xray-release-testing/aws-xray-sdk-dotnet/sdk/src/Core/AWSXRayRecorder.Core.csproj
dotnet add reference $HOME/xray-release-testing/aws-xray-sdk-dotnet/sdk/src/Handlers/AspNetCore/AWSXrayRecorder.Handlers.AspNetCore.csproj
dotnet add reference $HOME/xray-release-testing/aws-xray-sdk-dotnet/sdk/src/Handlers/AwsSdk/AWSXRayRecorder.Handlers.AwsSdk.csproj
echo "AWS X-Ray SDK added to the project."

# Start the server
echo "Starting the server..."
dotnet run
