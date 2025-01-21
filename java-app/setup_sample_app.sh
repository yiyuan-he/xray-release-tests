#!/bin/bash

set -ex

XRAY_SDK_REPO="https://github.com/aws/aws-xray-sdk-java.git"
SDK_CLONE_DIR="$HOME/xray-release-testing/aws-xray-sdk-java"

XRAY_SDK_CORE_ARTIFACT="aws-xray-recorder-sdk-core"
XRAY_SDK_V2_ARTIFACT="aws-xray-recorder-sdk-aws-sdk-v2"

# Prompt the user for the X-Ray SDK commit hash
while [[ -z "$COMMIT_HASH" ]]; do
    read -p "Enter the commit hash for the AWS X-Ray Java SDK (cannot be empty): " COMMIT_HASH
done

# Clone and checkout the specified commit hash
echo "Cloning $XRAY_SDK_REPO into $SDK_CLONE_DIR" || { echo "Failed to clone the AWS X-Ray SDK repo"; exit 1; }
git clone "$XRAY_SDK_REPO" "$SDK_CLONE_DIR"
cd "$SDK_CLONE_DIR"
git checkout "$COMMIT_HASH"

echo "Publishing the X-Ray SDK to Maven local (~/.m2/repository)..."

# We'll run Gradle with --info so it prints the line with "Inferred project: .. version: X"
# Then we grep out the version name.
GRADLE_OUTPUT=$(./gradlew publishToMavenLocal | tee /dev/tty)

# Find a line like: "Inferred project: aws-xray-sdk-java, vesion: 2.8.0-dev.118.uncommited+fab667"
# Extract the version substring:
SDK_VERSION=$(echo "$GRADLE_OUTPUT" | \
  grep -m1 "Inferred project:" | \
  sed -E 's/.*version: ([^ ]+)/\1/')

if [ -z "$SDK_VERSION" ]; then
    echo "Failed to parse version from Gradle output!"
    exit 1
fi

echo "X-Ray SDK version inferred: $SDK_VERSION"

# Return to sample app directory
cd -

echo "Using the new X-Ray SDK version ($SDK_VERSION) in our Maven app..."

mvn versions:use-dep-version \
  -Dincludes="com.amazonaws:${XRAY_SDK_CORE_ARTIFACT},com.amazonaws:${XRAY_SDK_V2_ARTIFACT}" \
  -DdepVersion="$SDK_VERSION" \
  -DforceVersion=true \

mvn versions:commit

echo "Verifying that both X-Ray dependencies point to the local version..."

POM_FILE="$(pwd)/pom.xml"
VALIDATION_FAILED=false

# Validate aws-xray-recorder-sdk-core
if ! grep -A 2 "<artifactId>$XRAY_SDK_CORE_ARTIFACT</artifactId>" "$POM_FILE" | grep -q "<version>$SDK_VERSION</version>"; then
  echo "ERROR: Validation failed - $XRAY_SDK_CORE_ARTIFACT doesn't match version $SDK_VERSION in $POM_FILE!"
  VALIDATION_FAILED=true
fi

# Validate aws-xray-recorder-sdk-aws-sdk-v2
if ! grep -A 2 "<artifactId>$XRAY_SDK_V2_ARTIFACT</artifactId>" "$POM_FILE" | grep -q "<version>$SDK_VERSION</version>"; then
  echo "ERROR: Validation failed - $XRAY_SDK_V2_ARTIFACT doesn't match version $SDK_VERSION in $POM_FILE!"
  VALIDATION_FAILED=true
fi

if [ "$VALIDATION_FAILED" = true ]; then
  echo "One or more validations failed. Exiting."
  exit 1
fi

mvn dependency:tree | grep xray

mvn clean install -DskipTests

# Run the sample app as a server
echo "Running the sample app using 'mvn spring-boot:run'..."
mvn spring-boot:run
