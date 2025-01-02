#!/bin/bash

set -e  # Exit on error

LINUX_XRAY_URL="https://s3.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/aws-xray-daemon-linux-3.x.zip"
MACOS_XRAY_URL="https://s3.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/aws-xray-daemon-macos-3.x.zip"
XRAY_SDK_REPO="https://github.com/aws/aws-xray-sdk-java.git"
SDK_CLONE_DIR="/tmp/aws-xray-sdk-java"
XRAY_DAEMON_DIR="$HOME/xray-daemon"
XRAY_DAEMON_BINARY=""
SERVER_PORT=8080

XRAY_SDK_GROUP_ID="com.amazonaws"
XRAY_SDK_ARTIFACT_ID="aws-xray-recorder-sdk-aws-sdk-v2"

MANUAL_TRACE_ENDPOINT="http://localhost:${SERVER_PORT}/generate-manual-traces"
AUTO_TRACE_ENDPOINT="http://localhost:${SERVER_PORT}/generate-automatic-traces"

# Prompt for commit hash or branch
read -p "Enter the commit hash (or branch) for the AWS X-Ray Java SDK [default=master]: " COMMIT_HASH
if [ -z "$COMMIT_HASH" ]; then
    COMMIT_HASH="master"
fi
echo "Will check out: $COMMIT_HASH"

validate_aws_credentials() {
    # Check if AWS environment variables are set
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ] && [ -n "$AWS_DEFAULT_REGION" ]; then
        echo "Using AWS credentials from environment variables."
        return 0
    fi

    # Otherwise, check if AWS CLI is configured
    if aws sts get-caller-identity &> /dev/null; then
        echo "Using AWS credentials from AWS CLI configuration."
        return 0
    fi

    # If neither are valid, exit
    echo "Error: AWS credentials are not configured."
    echo "Please configure credentials by either:"
    echo "  1. Exporting AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_DEFAULT_REGION"
    echo "  2. Setting up credentials with the AWS CLI (e.g., aws configure)"
    exit 1
}

detect_region() {
    # If AWS_DEFAULT_REGION is already set
    if [ -n "$AWS_DEFAULT_REGION" ]; then
        echo "Using AWS region from environment variable: $AWS_DEFAULT_REGION"
        REGION="$AWS_DEFAULT_REGION"
        return
    fi

    # Otherwise, check the AWS CLI config
    REGION=$(aws configure get region 2>/dev/null)
    if [ -n "$REGION" ]; then
        echo "Using AWS region from AWS CLI configuration: $REGION"
        export AWS_DEFAULT_REGION="$REGION"
        return
    fi

    # Otherwise, fail and exit
    echo "Error: AWS region is not configured."
    echo "Please configure a region by either:"
    echo "  1. Exporting AWS_DEFAULT_REGION"
    echo "  2. Setting up a default region via aws configure"
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

# Clone and checkout the specified commit hash
if [ -d "$SDK_CLONE_DIR" ]; then
    echo "Removing existing clone at $SDK_CLONE_DIR..."
    rm -rf "$SDK_CLONE_DIR"
fi

echo "Cloning $XRAY_SDK_REPO into $SDK_CLONE_DIR..."
git clone "$XRAY_SDK_REPO" "$SDK_CLONE_DIR"
cd "$SDK_CLONE_DIR"
git checkout "$COMMIT_HASH"

# Publish to Maven Local & capture the version
echo "Publishing the X-Ray SDK to Maven local (~/.m2/repository)..."

# We'll run Gradle with --info so it prints the line with "Inferred project: ... version: X"
# Then we grep out the version name.
GRADLE_OUTPUT=$(./gradlew publishToMavenLocal | tee /dev/tty)

# Find a line like: "Inferred project: aws-xray-sdk-java, version: 2.8.0-dev.118.uncommitted+fab6677"
# Extract the version substring:
SDK_VERSION=$(echo "$GRADLE_OUTPUT" | \
  grep -m1 "Inferred project:" | \
  sed -E 's/.*version: ([^ ]+)/\1/')

if [ -z "$SDK_VERSION" ]; then
  echo "Failed to parse version from Gradle output!"
  echo "Falling back to checking a 'publish' log line or default snapshot in ~/.m2."
  # Or exit 1, if you want the script to fail
  exit 1
fi

echo "X-Ray SDK version inferred: $SDK_VERSION"

cd - # Return to sample app directory

echo "Using the new X-Ray SDK version ($SDK_VERSION) in our Maven app..."

mvn versions:use-dep-version \
  -Dincludes="com.amazonaws:${XRAY_SDK_CORE_ARTIFACT},com.amazonaws:${XRAY_SDK_V2_ARTIFACT}" \
  -DdepVersion="$SDK_VERSION" \
  -DforceVersion=true

echo "Verifying that both X-Ray dependencies point to the local version..."

mvn dependency:tree | grep xray

mvn clean install -DskipTests

# Run the sample app as a server and hit the endpoints
echo "Running the sample app using 'mvn spring-boot:run'..."
mvn spring-boot:run > app.log 2>&1 &
SERVER_PID=$!
echo "Sample app started with PID $SERVER_PID"

# Wait a bit and check if the process is running
sleep 5
if ps -p $SERVER_PID > /dev/null; then
    echo "Sample app is running"
else
    echo "Error: Sample app failed to start. Check app.log for details."
    exit 1
fi

echo "Hitting manual trace endpoint: $MANUAL_TRACE_ENDPOINT"
MANUAL_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$MANUAL_TRACE_ENDPOINT")
echo "Manual endpoint returned: $MANUAL_CODE"

sleep 3

echo "Hitting automatic trace endpoint: $AUTO_TRACE_ENDPOINT"
AUTO_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$AUTO_TRACE_ENDPOINT")
echo "Automatic endpoint returned: $AUTO_CODE"

sleep 5

# Stop the server and X-Ray daemon
echo "Stopping the server..."
kill "$SERVER_PID" || true
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
echo "X-Ray daemon files removed."
echo "Cleaning up cloned X-Ray SDK repo..."
rm -rf $SDK_CLONE_DIR
echo "Cleaning up sample app build artifacts..."
rm -rf ./target
