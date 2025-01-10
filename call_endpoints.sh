#!/bin/bash

set -ex

SERVER_PORT=8080
MANUAL_TRACE_ENDPOINT="http://localhost:${SERVER_PORT}/generate-manual-traces"
AUTOMATIC_TRACE_ENDPOINT="http://localhost:${SERVER_PORT}/generate-automatic-traces"

echo "Hitting the manual trace endpoint..."
curl -s -o /dev/null -w "%{http_code}" $MANUAL_TRACE_ENDPOINT

sleep 5

echo "Hitting the automatic trace endpoint..."
curl -s -o /dev/null -w "%{http_code}" $AUTOMATIC_TRACE_ENDPOINT

echo "Traces should now be visible in the AWS X-Ray Console"
