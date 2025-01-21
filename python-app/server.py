from flask import Flask, jsonify
import boto3
from aws_xray_sdk.core import xray_recorder, patch
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware

app = Flask(__name__)

libs_to_patch = ('boto3',)
patch(libs_to_patch)

xray_recorder.configure(
    sampling=True,
    context_missing='LOG_ERROR',
    daemon_address='127.0.0.1:2000',
    service="PythonXRayTestApp"
)
XRayMiddleware(app, xray_recorder)

s3_client = boto3.client('s3')

@app.route('/generate-automatic-traces', methods=['GET'])
def automatic_trace():
    response = s3_client.list_buckets()
    bucket_names = [bucket['Name'] for bucket in response.get('Buckets', [])]
    return jsonify(bucket_names)

@app.route('/generate-manual-traces', methods=['GET'])
def manual_trace():
    # Start a subsegment for the S3 API call
    with xray_recorder.in_subsegment('MockOperation1') as subsegment:
        print("Simulating mock operation 1")
        # Start a nested subsegment for extracting bucket names
        with xray_recorder.in_subsegment('ProcessMockData'):
            mock_buckets = ['mock-bucket1', 'mock-bucket2', 'mock-bucket3']
            # Add metadata to the subsegment
            subsegment.put_annotation('first_bucket_name', mock_buckets[0])
    # Make a second S3 API call and instrument with a sibling subsegment
    with xray_recorder.in_subsegment('MockOperation2'):
        print("Simulating mock operation 2")
    return jsonify(mock_buckets)

if __name__ == '__main__':
    app.run(debug=True, port=8080, use_reloader=False)
