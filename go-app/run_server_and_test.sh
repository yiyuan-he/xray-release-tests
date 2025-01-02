#!/bin/bash

# Define variables
LINUX_XRAY_URL="https://s3.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/aws-xray-daemon-linux-3.x.zip"
MACOS_XRAY_URL="https://s3.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/aws-xray-daemon-macos-3.x.zip"
XRAY_DAEMON_DIR="$HOME/xray-daemon"
XRAY_DAEMON_BINARY=""
SERVER_PORT=8080
MANUAL_TRACE_ENDPOINT="http://localhost:${SERVER_PORT}/generate-manual-traces"
AUTOMATIC_TRACE_ENDPOINT="http://localhost:${SERVER_PORT}/generate-automatic-traces"
XRAY_SDK_REPO="github.com/aws/aws-xray-sdk-go"

# Prompt user for the commit hash or default to "latest"
read -p "Enter the commit hash (or branch) of the AWS X-Ray Go SDK [default=master]: " COMMIT_HASH
if [ -z "$COMMIT_HASH" ]; then
    COMMIT_HASH="latest"
    echo "Using the latest commit of the AWS X-Ray SDK."
else
    echo "Using commit hash: $COMMIT_HASH"
fi

# Validate AWS credentials (either environment variables or AWS CLI configuration)
validate_aws_credentials() {
    # Check if AWS environment variables are set
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ] && [ -n "$AWS_DEFAULT_REGION" ]; then
        echo "Using AWS credentials from environment variables."
        return 0
    fi

    # Check if AWS CLI configuration works
    if aws sts get-caller-identity &> /dev/null; then
        echo "Using AWS credentials from AWS CLI configuration."
        return 0
    fi

    # If neither is valid, exit with an error
    echo "Error: AWS credentials are not configured."
    echo "Please configure credentials by either:"
    echo "  1. Exporting AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_DEFAULT_REGION"
    echo "  2. Setting up credentials with the AWS CLI (e.g., aws configure)"
    exit 1
}

# Detect the AWS region
detect_region() {
    if [ -n "$AWS_DEFAULT_REGION" ]; then
        echo "Using AWS region from environment variable: $AWS_DEFAULT_REGION"
        REGION=$AWS_DEFAULT_REGION
        return
    fi

    REGION=$(aws configure get region 2>/dev/null)
    if [ -n "$REGION" ]; then
        echo "Using AWS region from AWS CLI configuration: $REGION"
        export AWS_DEFAULT_REGION=$REGION
        return
    fi

    echo "Error: AWS region is not configured."
    echo "Please configure a region by either:"
    echo "  1. Exporting AWS_DEFAULT_REGION"
    echo "  2. Setting up a default region in AWS CLI (e.g., aws configure)"
    exit 1
}


validate_aws_credentials
detect_region

# Detect the OS and set the URL and binary name
OS=$(uname -s)
case "$OS" in
    Linux*)  
        XRAY_URL=$LINUX_XRAY_URL
        XRAY_DAEMON_BINARY="$XRAY_DAEMON_DIR/xray"
        ;;
    Darwin*) 
        XRAY_URL=$MACOS_XRAY_URL
        XRAY_DAEMON_BINARY="$XRAY_DAEMON_DIR/xray_mac"
        ;;
    *) 
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

echo "Detected OS: $OS"
echo "Using X-Ray daemon URL: $XRAY_URL"
echo "Using AWS region: $REGION"

# Download and extract the X-Ray daemon
if [ ! -f "$XRAY_DAEMON_BINARY" ]; then
    echo "X-Ray daemon binary not found. Downloading and extracting..."
    mkdir -p "$XRAY_DAEMON_DIR"
    TEMP_ZIP="$XRAY_DAEMON_DIR/xray-daemon.zip"
    curl -o "$TEMP_ZIP" "$XRAY_URL" || { echo "Failed to download X-Ray daemon"; exit 1; }
    unzip -o "$TEMP_ZIP" -d "$XRAY_DAEMON_DIR" || { echo "Failed to extract X-Ray daemon"; exit 1; }
    chmod +x "$XRAY_DAEMON_BINARY"
    rm -f "$TEMP_ZIP"
else
    echo "X-Ray daemon binary already exists at $XRAY_DAEMON_BINARY"
fi

# Start the X-Ray Daemon
echo "Starting the X-Ray daemon..."
"$XRAY_DAEMON_BINARY" -o -n $REGION &
XRAY_DAEMON_PID=$!
echo "X-Ray daemon started with PID: $XRAY_DAEMON_PID"

# Wait for the daemon to initialize
sleep 5

# Update the AWS X-Ray SDK to the specified commit hash
echo "Updating AWS X-Ray SDK to commit: $COMMIT_HASH..."
go get $XRAY_SDK_REPO@$COMMIT_HASH || { echo "Failed to update the AWS X-Ray SDK"; exit 1; }
go mod tidy

# Build the Go server
echo "Building the server..."
go build -o server main.go || { echo "Failed to build the server"; exit 1; }

# Start the server
echo "Starting the server..."
./server &
SERVER_PID=$!
echo "Server started with PID: $SERVER_PID"

# Wait for the server to initialize
echo "Waiting for server to be ready..."
for i in {1..10}; do
    if ps -p $SERVER_PID > /dev/null; then
        echo "Server is ready!"
        break
    fi
    echo "Waiting..."
    sleep 1
done

# Test the endpoints
echo "Testing endpoints..."
sleep 5

echo "Hitting the manual trace endpoint..."
MANUAL_TRACE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $MANUAL_TRACE_ENDPOINT)
if [ "$MANUAL_TRACE_STATUS" -ne 200 ]; then
    echo "Error: Manual trace endpoint returned status $MANUAL_TRACE_STATUS"
    exit 1
else
    echo "Manual trace endpoint returned status $MANUAL_TRACE_STATUS"
fi

echo "Waiting for X-Ray daemon to process the first trace..."
sleep 5

echo "Hitting the automatic trace endpoint..."
AUTOMATIC_TRACE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $AUTOMATIC_TRACE_ENDPOINT)
if [ "$AUTOMATIC_TRACE_STATUS" -ne 200 ]; then
    echo "Error: Automatic trace endpoint returned status $AUTOMATIC_TRACE_STATUS"
    exit 1
else
    echo "Automatic trace endpoint returned status $AUTOMATIC_TRACE_STATUS"
fi

sleep 5

# Stop the server and X-Ray daemon
echo "Stopping the server..."
kill $SERVER_PID
if kill -0 $XRAY_DAEMON_PID 2>/dev/null; then
    kill $XRAY_DAEMON_PID
    echo "X-Ray daemon stopped."
else
    echo "X-Ray daemon was not running."
fi

# Provide instructions to check the AWS Console
echo "Traces should now be visible in the AWS X-Ray Console."
echo "Visit the X-Ray Console and filter traces by service name."

# Cleanup 
echo "Cleaning up X-Ray daemon files..."
rm -rf $HOME/xray-daemon
echo "Cleaning up sample app binary..."
rm ./server
