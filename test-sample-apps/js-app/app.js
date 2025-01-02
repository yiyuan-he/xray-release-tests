const AWSXRay = require('aws-xray-sdk-core');
const XRayExpress = require('aws-xray-sdk-express');
const express = require('express');
const { S3Client, ListBucketsCommand } = require('@aws-sdk/client-s3');

const app = express();
// start segment for subsequent requests
app.use(XRayExpress.openSegment('MyApp'));

// create an S3 client that automatically captures API calls
const s3Client = AWSXRay.captureAWSv3Client(new S3Client({ region: 'us-west-2' }));

// automatic subsegment management
app.get('/generate-automatic-traces', async (req, res) => {
  try {
    const data = await s3Client.send(new ListBucketsCommand());

    const buckets = data.Buckets.map(bucket => ({
      name: bucket.Name,
      creation_date: bucket.CreationDate.toISOString()
    }));

    res.json(buckets);
  } catch (err) {
    res.status(500).send(`Unable to list buckets: ${err.message}`);
  }
});

// manual subsegment management
app.get('/generate-manual-traces', async (req, res) => {
  // create manual subsegment
  AWSXRay.captureAsyncFunc('CustomSubsegment', async (subsegment) => {
    try {
      const data = await s3Client.send(new ListBucketsCommand());

      const buckets = data.Buckets.map(bucket => ({
        name: bucket.Name,
        creation_date: bucket.CreationDate.toISOString()
      }));
      res.json(buckets);
    } catch (err) {
      subsegment.addError(err);
      res.status(500).send(`Unable to list buckets: ${err.message}`);
    }

    subsegment.close();
  });

});

// End the X-Ray segment for the request
app.use(XRayExpress.closeSegment());

// Start the server
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
