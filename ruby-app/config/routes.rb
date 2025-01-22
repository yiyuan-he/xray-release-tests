require 'aws-sdk-s3'
require 'aws-xray-sdk'

Rails.application.routes.draw do
  # Automatic traces route
  get '/generate-automatic-traces', to: proc { |env|
    s3_client = Aws::S3::Client.new
    response = s3_client.list_buckets
    bucket_names = response.buckets.map(&:name)

    [
      200,
      { 'Content-Type' => 'application/json' },
      [bucket_names.to_json]
    ]
  }

  # Manual traces route
  get '/generate-manual-traces', to: proc { |env|
    # Start a subsegment for MockOperation1
    subsegment1 = XRay.recorder.begin_subsegment('MockOperation1')
    begin
      Rails.logger.info 'Simulating Mock Operation 1'

      # Start a nested subsegment for processing mock data
      subsegment2 = XRay.recorder.begin_subsegment('ProcessMockData')
      begin
        mock_buckets = %w[mock-bucket1 mock-bucket2 mock-bucket3]
        subsegment2.annotations.update(first_bucket_name: mock_buckets.first)
      ensure
        XRay.recorder.end_subsegment # End ProcessMockData
      end
    ensure
      XRay.recorder.end_subsegment # End MockOperation1 subsegment
    end

    # Start another subsegment for MockOperation2
    subsegment3 = XRay.recorder.begin_subsegment('MockOperation2')
    begin
      Rails.logger.info 'Simulating Mock Operation 2'
    ensure
      XRay.recorder.end_subsegment # End MockOperation2 subsegment
    end

    [
      200,
      { 'Content-Type' => 'application/json' },
      [mock_buckets.to_json]
    ]
  }
end
