from flask import Flask, jsonify
import boto3
import logging
from aws_xray_sdk.core import xray_recorder

app = Flask(__name__)

xray_recorder.configure(
    sampling=False,
    context_missing='LOG_ERROR',
    daemon_address='127.0.0.1:2000',
    service="PythonXRayTestAppManual"
)

s3_client = boto3.client('s3')

@app.route('/generate-manual-traces', methods=['GET'])
def manual_trace():
    # Start a root segment for the HTTP requesst
    with xray_recorder.in_segment('ManualTraceHandler') as segment:
        # Start a subsegment for the S3 API call
        with xray_recorder.in_subsegment('S3ListBucketsCall1'):
            response = s3_client.list_buckets()
            # Start a nested subsegment for extracting bucket names
            with xray_recorder.in_subsegment('ExtractBucketNames'):
                bucket_names = [bucket['Name'] for bucket in response.get('Buckets', [])]
                # Add metadata to the subsegment
                if len(bucket_names) > 0:
                    segment.put_annotation('first_bucket_name', bucket_names[0])
        # Make a second S3 API call and instrument with a sibling subsegment
        with xray_recorder.in_subsegment('S3ListbucketsCall2'):
            s3_client.list_buckets()
    return jsonify(bucket_names)

if __name__ == '__main__':
    app.run(debug=True, port=8080, use_reloader=False)