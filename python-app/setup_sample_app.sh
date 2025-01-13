#!/bin/bash

set -ex

# Define variables
PYTHON_VENV="venv"
REQUIREMENTS_FILE="requirements.txt"
MANUAL_FILE="manual.py"

# Promp the user for the AWS X-Ray SDK commit hash or version
read -p "Enter the commit hash (or branch) for the AWS X-Ray Python SDK [default=master]: " SDK_COMMIT

# Determine appropriate entry for requirements.txt
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
