# Prerequisites
- Ensure Java 8 or Java 11 is installed.
- Set up AWS credentials with environment variables or cli configuration.

# Set up
1. Clone and `cd` into the repo.
2. Make the test script executable:
```{bash}
chmod + x run_server_and_test.sh
```
3. Run script:
```{bash}
./run_server_and_test.sh
```
4. After the script runs successfully, check the AWS console for the X-Ray traces.
