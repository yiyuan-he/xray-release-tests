package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-xray-sdk-go/instrumentation/awsv2"
	"github.com/aws/aws-xray-sdk-go/xray"
)

var s3Client *s3.Client

func main() {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("us-west-2"))
	if err != nil {
		log.Fatalf("unable to load AWS configuration: %v", err)
	}

	// Initialize an S3 client
	s3Client = s3.NewFromConfig(cfg)

	// Initialize X-Ray configuration
	xray.Configure(xray.Config{
		DaemonAddr:     "127.0.0.1:2000", // default
		ServiceVersion: "1.2.3",
	})

	// Set up HTTP routes
	http.HandleFunc("/generate-manual-traces", handleManualTrace)
	http.HandleFunc("/generate-automatic-traces", handleAutomaticTrace)

	// Start the server
	port := 8080
	fmt.Printf("Server running on http://localhost:%d\n", port)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%d", port), nil))
}

func handleManualTrace(w http.ResponseWriter, r *http.Request) {
	// Start a root segment for the HTTP request
	ctx, seg := xray.BeginSegment(r.Context(), "ManualTraceHandler")
	defer seg.Close(nil)

	// Call mock list buckets function
	buckets, err := listBuckets(ctx) // Pass context
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to list buckets: %v", err), http.StatusInternalServerError)
		return
	}

	// Write the bucket names as JSON response
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(buckets)
}

// Manual instrumentation of S3 API Call
func listBuckets(ctx context.Context) ([]string, error) {
	// Start a subsegment for the S3 API call
	opCallCtx, opSubSeg := xray.BeginSubsegment(ctx, "MockOperation1")
	defer opSubSeg.Close(nil)

	// Simulate the first mock operation
	fmt.Println("Simulating Mock Operation 1: Listing buckets")
	mockBuckets := []string{"mock-bucket1", "mock-bucket2", "mock-bucket3"}

	// Start a nested subsegment for extracting bucket names
	_, extractSubSeg := xray.BeginSubsegment(opCallCtx, "ProcessMockData")
	defer extractSubSeg.Close(nil)

	// Add metadata to the subsegment
	extractSubSeg.AddMetadata("firstBucketName", mockBuckets[0])

	// Make a second S3 API call and instrument with a sibling subsegment
	_, opSubSeg2 := xray.BeginSubsegment(ctx, "MockOperation2")
	defer opSubSeg2.Close(nil)

	return mockBuckets, nil
}

func handleAutomaticTrace(w http.ResponseWriter, r *http.Request) {
	// Start a root segment for the HTTP request
	ctx, seg := xray.BeginSegment(r.Context(), "AutomaticTraceHandler")
	defer seg.Close(nil)

	// Load AWS configuration with automatic instrumentation
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion("us-west-2"))
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to load AWS configuration: %v", err), http.StatusInternalServerError)
		return 
	}

	// Automatically instrument AWS SDK v2
	awsv2.AWSV2Instrumentor(&cfg.APIOptions)

	// Create a new S3 client with automatic instrumentation
	autoS3Client := s3.NewFromConfig(cfg)

	// Make the API call to list buckets
	output, err := autoS3Client.ListBuckets(ctx, &s3.ListBucketsInput{})
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to list buckets: %v", err), http.StatusInternalServerError)
		return
	}

	// Extract bucket names
	var bucketNames[]string
	for _, bucket := range output.Buckets {
		bucketNames = append(bucketNames, *bucket.Name)
	}

	// Write the bucket names as JSON response
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(bucketNames)
}
