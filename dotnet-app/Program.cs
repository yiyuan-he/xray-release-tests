using Amazon;
using Amazon.S3;
using Amazon.XRay.Recorder.Core;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = WebApplication.CreateBuilder(args);

// Trace all AWS SDK calls
AWSSDKHandler.RegisterXRayForAllServices();

// Add AWS SDK for S3
AmazonS3Client s3Client = new AmazonS3Client(RegionEndpoint.USWest2);

var app = builder.Build();

// capture incoming HTTP requests
app.UseXRay("MyApp");

app.MapGet("/generate-automatic-traces", async () =>
{
    try
    {
        // List the S3 buckets
        var response = await s3Client.ListBucketsAsync();

        var buckets = response.Buckets.Select(bucket => new
        {
            name = bucket.BucketName,
            creation_date = bucket.CreationDate
        }).ToList();

        return Results.Ok(buckets);
    }
    catch (Exception ex)
    {
        return Results.Problem(ex.Message);
    }
});

app.MapGet("/generate-manual-traces", async () =>
{
    AWSXRayRecorder.Instance.BeginSubsegment("ManualSubsegment");
    try
    {
        // List the S3 buckets
        var response = await s3Client.ListBucketsAsync();

        var buckets = response.Buckets.Select(bucket => new
        {
            name = bucket.BucketName,
            creation_date = bucket.CreationDate
        }).ToList();

        return Results.Ok(buckets);
    }
    catch (Exception ex)
    {
        return Results.Problem(ex.Message);
    }
    finally
    {
        AWSXRayRecorder.Instance.EndSubsegment();
    }
});

app.Run();
