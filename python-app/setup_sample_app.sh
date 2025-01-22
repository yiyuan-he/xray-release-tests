#!/bin/bash

set -ex

# Define variables
PYTHON_VENV="venv"
REQUIREMENTS_FILE="requirements.txt"
MANUAL_FILE="manual.py"

# Prompt the user for the X-Ray SDK commit hash
while [[ -z "$COMMIT_HASH" ]]; do
    read -p "Enter the commit hash for the AWS X-Ray Python SDK (cannot be empty): " COMMIT_HASH
done

# Use the specified commit hash in our requirements.txt
SDK_ENTRY="git+https://github.com/aws/aws-xray-sdk-python.git@$COMMIT_HASH#egg=aws-xray-sdk"
echo "Using the specified commit hash: $COMMIT_HASH"

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
}

# Validate Python environment
setup_python_env

python server.py
