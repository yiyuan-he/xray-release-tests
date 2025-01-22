#!/bin/bash

# Define variable
GEMFILE="Gemfile"
GEMFILE_CONFIGURATION="Gemfile_configuration"
AWS_SDK_S3_LINE="gem 'aws-sdk-s3'"

# Prompt the user for the X-Ray SDK commit hash
while [[ -z "$COMMIT_HASH" ]]; do
    read -p "Enter the commit hash for the AWS X-Ray Ruby SDK (cannot be empty): " COMMIT_HASH
done

# Use the specified commit for our X-Ray SDK dependency
AWS_XRAY_SDK_LINE="gem 'aws-xray-sdk', git: 'https://github.com/aws/aws-xray-sdk-ruby.git', ref: '$COMMIT_HASH', require: ['aws-xray-sdk/facets/rails/railtie']"

# Overwrite the Gemfile with the base contents
echo "Resetting the Gemfile to the base configuration..."
cp "$GEMFILE_CONFIGURATION" "$GEMFILE"

echo "Adding dependencies to the Gemfile..."
{
    echo ""
    echo "$AWS_SDK_S3_LINE" 
    echo "$AWS_XRAY_SDK_LINE"
} >> "$GEMFILE"

echo "Running bundle install..."
bundle install

echo "Starting server..."
rails server
