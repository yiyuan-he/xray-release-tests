# Description
This directory contains sample apps and test scripts for our X-Ray SDKs in various languages.
These sample apps and test scripts provide a simple sanity test for the end-to-end trace generation process of our X-Ray Java SDK.

At a high-level, the test script will:
1. Pull in a version of the X-Ray SDK based on user input and build the sample app.
2. Pull in the binary for the X-Ray Daemon for the user's OS (either MacOS or Linux).
3. Start the sample app server and generate traces by hitting the two endpoints (manual and auto).
    - The `generate-manual-traces` endpoint validates the manual segment/subsegment management functionality is intact.
    - The `generate-automatic-traces` endpoint validates the automatic segment/subsegment management functionality the AWS SDK is intact.
4. After the script finishes, the user should be able to log into their AWS account and see that the traces 
   were correctly generated.
