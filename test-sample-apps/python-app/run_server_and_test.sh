#!/bin/bash

# Define variables
PYTHON_VENV="venv"
REQUIREMENTS_FILE="requirements.txt"
LINUX_XRAY_URL="https://s3.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/aws-xray-daemon-linux-3.x.zip"
MACOS_XRAY_URL="https://s3.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/aws-xray-daemon-macos-3.x.zip"
XRAY_DAEMON_DIR="$HOME/xray-daemon"
XRAY_DAEMON_BINARY=""
MANUAL_ROUTE="http://localhost:8080/generate-manual-traces"
AUTOMATIC_ROUTE="http://localhost:8080/generate-automatic-traces"
MANUAL_FILE="manual.py"
AUTOMATIC_FILE="automatic.py"
SERVER_PORT=8080

# Prompt the user for the AWS X-Ray SDK commit hash or version
read -p "Enter the AWS X-Ray SDK commit hash to test (press Enter for latest commit): " SDK_COMMIT

# Determine the appropriate entry for requirements.txt
if [ -z "$SDK_COMMIT" ]; then
    # Default to the latest commit on the master branch
    SDK_ENTRY="git+https://github.com/aws/aws-xray-sdk-python.git@master#egg=aws-xray-sdk"
    echo "Using the latest commit on the master branch."
else
    # Use the specified commit hash
    SDK_ENTRY="git+https://github.com/aws/aws-xray-sdk-python.git@$SDK_COMMIT#egg=aws-xray-sdk"
    echo "Using the specified commit hash: $SDK_COMMIT"
fi

# Create or overwrite the requirements.txt file
cat <<EOF > requirements.txt
flask
boto3
$SDK_ENTRY
EOF

# Ensure Python virtual environment is set up
setup_python_env() {
    echo "Setting up Python environment..."
    if [ ! -d "$PYTHON_VENV" ]; then
        echo "Python virtual environment not found. Creating one..."
        python3 -m venv $PYTHON_VENV || { echo "Failed to create Python virtual environment"; exit 1; }
    fi

    # Activate the virtual environment
    source $PYTHON_VENV/bin/activate || { echo "Failed to activate Python virtual environment"; exit 1; }

    # Check for requirements.txt
    if [ -f "$REQUIREMENTS_FILE" ]; then
        echo "Installing dependencies from $REQUIREMENTS_FILE..."
        pip install -r $REQUIREMENTS_FILE || { echo "Failed to install dependencies"; exit 1; }
    else
        echo "Error: $REQUIREMENTS_FILE not found."
        exit 1
    fi

    deactivate
}

# Validate Python environment
setup_python_env

# Re-activate virtual environment for the script's execution
source $PYTHON_VENV/bin/activate || { echo "Failed to activate Python virtual environment"; exit 1; }

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
    echo "  2. Setting up a default region in AWS CLI (e.g. aws configure)"
    exit 1
}

# Validate AWS credentials
validate_aws_credentials() {
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "Using AWS credentials from environment variables."
        return 0
    fi

    if aws sts get-caller-identity &> /dev/null; then
        echo "Using AWS credentials from AWS CLI configuration."
        return 0
    fi

    echo "Error: AWS credentials are not configured."
    echo "Please configure credentials by either:"
    echo "  1. Exporting AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_DEFAULT_REGION"
    echo "  2. Setting up credentials with the AWS CLI (e.g. aws configure)"
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

# Check for existing X-Ray daemon
existing_daemon_pid=$(lsof -ti:2000)
if [ -n "$existing_daemon_pid" ]; then
    echo "An existing X-Ray daemon is running on port 2000. Terminating..."
    kill "$existing_daemon_pid"
    sleep 2
fi

# Download and extract the X-Ray Daemon
if [ ! -f "$XRAY_DAEMON_BINARY" ]; then
    echo "X-Ray daemon binary not found. Downloading and extracting..."
    mkdir -p "$XRAY_DAEMON_DIR"
    TEMP_ZIP="$XRAY_DAEMON_DIR/xray-daemon.zip"
    curl -o "$TEMP_ZIP" "$XRAY_URL" || { echo "Failed to download X-Ray daemon"; exit 1; }
    unzip -o "$TEMP_ZIP" -d "$XRAY_DAEMON_DIR" || { echo "Failed to extract X-Ray daemon"; exit 1; }
    chmod +x "$XRAY_DAEMON_BINARY"
    rm -f "$TEMP_ZIP"
fi

# Start the X-Ray daemon
echo "Starting the X-Ray daemon..."
"$XRAY_DAEMON_BINARY" -o -n $REGION &
XRAY_DAEMON_PID=$!
echo "X-Ray daemon started with PID: $XRAY_DAEMON_PID"

# Wait for the daemon to initialize
sleep 5

stop_process() {
    local pid=$1
    if kill -0 $pid 2>/dev/null; then
        echo "Stopping process with PID $pid..."
        kill $pid
        wait $pid 2>/dev/null || true
        echo "Process $pid stopped."
    else
        echo "Process $pid is not running."
    fi
}

# Test the manual.py server
echo "Starting the manual.py server..."
python $MANUAL_FILE &
MANUAL_PID=$!
echo "manual.py server started with PID: $MANUAL_PID"

# Wait for the server to initialize
echo "Waiting for server to be ready..."
for i in {1..10}; do
    if curl -s -o /dev/null $MANUAL_ROUTE; then
        echo "manual.py server is ready!"
        break
    fi
    echo "Waiting..."
    sleep 1
done

sleep 5

echo "Hitting the manual trace endpoint..."
MANUAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $MANUAL_ROUTE)
if [ "$MANUAL_STATUS" -ne 200 ]; then
    echo "Error: Manual trace endpoint returned status $MANUAL_STATUS"
    exit 1
else
    echo "Manual trace endpoint returned status $MANUAL_STATUS"
fi

# Stop the manual.py server
echo "Stopping the manual.py server..."
kill $MANUAL_PID

sleep 5

# Test the automatic.py server
echo "Starting the automatic.py server..."
python $AUTOMATIC_FILE &
AUTOMATIC_PID=$!
echo "automatic.py server started with PID: $AUTOMATIC_PID"

# Wait for the server to initialize
echo "Waiting for automatic.py server to be ready..."
for i in {1..10}; do
    if curl -s -o /dev/null $AUTOMATIC_ROUTE; then
        echo "automatic.py server is ready!"
        break
    fi
    echo "Waiting..."
    sleep 1
done

sleep 5

echo "Hitting the automatic trace endpoint..."
AUTOMATIC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $AUTOMATIC_ROUTE)
if [ "$AUTOMATIC_STATUS" -ne 200 ]; then
    echo "Error: Automatic trace endpoint returned status $AUTOMATIC_STATUS"
    exit 1
else
    echo "Automatic trace endpoint returned status $AUTOMATIC_STATUS"
fi

# Stop the automatic.py server
echo "Stopping the automatic.py server..."
kill $AUTOMATIC_PID

sleep 5

# Stop the X-Ray Daemon
echo "Stopping the X-Ray daemon..."
kill $XRAY_DAEMON_PID

# Provide instructions to check the AWS Console
echo "Traces should now be visible in the AWS X-Ray Console."
echo "Visit the X-Ray Console and filter traces by service name."

# Cleanup 
echo "Cleaning up X-Ray daemon files..."
rm -rf $HOME/xray-daemon
echo "X-Ray daemon files removed."
echo "Deactivating the Python virtual environment..."
deactivate