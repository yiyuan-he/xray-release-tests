#!/bin/bash

set -e  # Exit on error

XRAY_SDK_REPO="https://github.com/aws/aws-xray-sdk-java.git"
SDK_CLONE_DIR="/tmp/aws-xray-sdk-java"

XRAY_SDK_GROUP_ID="com.amazonaws"
XRAY_SDK_ARTIFACT_ID="aws-xray-recorder-sdk-aws-sdk-v2"

MANUAL_TRACE_ENDPOINT="http://localhost:8080/generate-manual-traces"
AUTO_TRACE_ENDPOINT="http://localhost:8080/generate-automatic-traces"

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

# Prompt for commit hash or branch
read -p "Enter the commit hash (or branch) for the AWS X-Ray Java SDK [default=master]: " COMMIT_HASH
if [ -z "$COMMIT_HASH" ]; then
    COMMIT_HASH="master"
fi
echo "Will check out: $COMMIT_HASH"

# Clone and checkout
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

echo "Hitting automatic trace endpoint: $AUTO_TRACE_ENDPOINT"
AUTO_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$AUTO_TRACE_ENDPOINT")
echo "Automatic endpoint returned: $AUTO_CODE"

sleep 5

echo "Stopping sample app..."
kill "$SERVER_PID" || true
sleep 2

echo "Done! Check the AWS X-Ray console for traces."
