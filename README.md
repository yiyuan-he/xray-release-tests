# Description
This directory contains sample apps and test scripts for our X-Ray SDKs in various languages.
These sample apps and test scripts provide a simple sanity test for the end-to-end trace generation process of our X-Ray SDKs.

At a high-level, the test scripts will:
1. Pull in a version of the X-Ray SDK based on user input and build the sample app.
2. Pull in the binary for the X-Ray daemon for the user's OS (either MacOS or Linux).
3. Start the X-Ray daemon on port `2000`.
4. Start the sample app server on port `8080` and generate traces by hitting the two endpoints (manual and auto).
    - The `generate-manual-traces` endpoint validates the manual segment/subsegment management functionality is intact.
    - The `generate-automatic-traces` endpoint validates the automatic segment/subsegment management functionality the AWS SDK is intact.
5. After the script finishes, the user should be able to log into their AWS account and see that the traces 
   were correctly generated.

# Prerequisites
- Set up AWS credentials with environment variables or cli configuration
- Install the appropriate versions for each language:
    - **.NET**: 9.0 or above
    - **Go**: 1.19 or above
    - **Java**: 8 or 11
    - **Python**: 3.7 to 3.11
    - **JavaScript**: node.js version 14.x or above
    - **Ruby**: 2.3.6 or above

# Instructions
1. **Run the X-Ray Daemon Setup Script**

Execute the following command the set up the X-Ray daemon:
```bash
./validate_and_initialize_xray_daemon.sh <aws-region>
```
Note: the script will default to `us-east-1` if no region is passed as an argument.

2. **Navigate to the Language Directory**

Open a new terminal session and navigate to the directory of the language you want to test. For example, for Java:
```bash
cd java-app
```

3. **Run the Sample App Setup Script**

In the same directory, run the sample app setup script:
```bash
./setup_sample_app.sh
```
The script will prompt you to enter a hash commit. This can be found at:
- **Java**: https://github.com/aws/aws-xray-sdk-java/commits/master/
- **Go**: https://github.com/aws/aws-xray-sdk-go/commits/master/
- **Python**: https://github.com/aws/aws-xray-sdk-python/commits/master/
- **JavaScript**: https://github.com/aws/aws-xray-sdk-node/commits/master/
- **.NET**: https://github.com/aws/aws-xray-sdk-dotnet/commits/master/

Wait until the server starts successfully.

4. **Run the Call Endpoint Script.**

Open a new terminal session and navigate back to the `/xray-release-tests` directory. Then run the call endpoint script:
```bash
./call_endpoints.sh
```

5. **Verify Traces in AWS CloudWatch**

Go to the CloudWatch section in the AWS Console and verify that the traces are correctly generated.

Ensure that there are 2 traces that correspond to the `/generate-manual-traces` and `/generate-automatic-traces call`.

* Validate that `/generate-automatic-traces` has an S3 Subsegment
* Validate that `/generate-manual-traces` has three Subsegments named MockOperation1, ProcessMockData, and MockOperation2
