package com.example;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.amazonaws.xray.AWSXRayRecorder;
import com.amazonaws.xray.AWSXRayRecorderBuilder;
import com.amazonaws.xray.entities.Segment;
import com.amazonaws.xray.entities.Subsegment;
import com.amazonaws.xray.interceptors.TracingInterceptor;

import software.amazon.awssdk.core.client.config.ClientOverrideConfiguration;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.Bucket;
import software.amazon.awssdk.services.s3.model.ListBucketsRequest;

import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

@SpringBootApplication
@RestController
public class MainApplication {

    private final S3Client s3Client;
    private final S3Client tracedS3Client;
    private final AWSXRayRecorder xrayRecorder;

    public MainApplication() {
        xrayRecorder = AWSXRayRecorderBuilder.defaultRecorder();
        // Create the S3 client
        s3Client = S3Client.create();
        tracedS3Client = S3Client.builder()
            .overrideConfiguration(
                ClientOverrideConfiguration.builder()
                    .addExecutionInterceptor(new TracingInterceptor())
                    .build()
            )
            .build();
    }

    public static void main(String[] args) {
        SpringApplication.run(MainApplication.class, args);
    }

    @GetMapping("/generate-manual-traces")
    public List<String> listBuckets() {
        // Start the parent segment
        Segment parentSegment = xrayRecorder.beginSegment("ManualTraceHandler");
        parentSegment.putAnnotation("HandlerType", "Manual");

        List<String> mockBuckets = null;

        try {
            Subsegment mockSubSeg1 = xrayRecorder.beginSubsegment("MockOperation1");
            mockSubSeg1.putAnnotation("Operation", "MockOperation1");

            try {
                System.out.println("Simulating Mock Operation 1: Listing buckets");
                mockBuckets = Arrays.asList("mock-bucket1", "mock-bucket2", "mock-bucket3");

                Subsegment extractSubSeg = xrayRecorder.beginSubsegment("ProcessMockData");
                try {
                    String firstBucketName = mockBuckets.get(0);
                    extractSubSeg.putAnnotation("FirstBucketName", firstBucketName);
                } catch (Exception e) {
                    extractSubSeg.addException(e);
                    throw e;
                } finally {
                    xrayRecorder.endSubsegment(); // End "ProcessMockData"
                }

            } catch (Exception e) {
                mockSubSeg1.addException(e);
                throw e;
            } finally {
                xrayRecorder.endSubsegment(); // End "MockOperation1"
            }


            // Create a sibling subsegment
            Subsegment mockSubSeg2 = xrayRecorder.beginSubsegment("MockOperation2");
            mockSubSeg2.putAnnotation("Operation", "MockOperation2");

            try {
                System.out.println("Simulating Mock Operation 2: Additional processing");
            } catch (Exception e) {
                mockSubSeg2.addException(e);
                throw e;
            } finally {
                xrayRecorder.endSubsegment(); // End "MockOperation2"
            }

            return mockBuckets; // Return the list of buckets

        } catch (Exception e) {
            parentSegment.addException(e);
            throw new RuntimeException("Failed to generate manual instrumentation: " + e.getMessage());
        } finally {
            xrayRecorder.endSegment(); // End "ManualTraceHandler"
        }
    }

    @GetMapping("/generate-automatic-traces")
    public List<String> listBucketsAuto() {
        Segment parentSegment = xrayRecorder.beginSegment("AutomaticTraceHandler");
        parentSegment.putAnnotation("HandlerType", "Automatic");

        try {
            return tracedS3Client.listBuckets(ListBucketsRequest.builder().build())
                                 .buckets()
                                 .stream()
                                 .map(Bucket::name)
                                 .collect(Collectors.toList());
        } catch (Exception e) {
            throw e;
        } finally {
            xrayRecorder.endSegment();
        }
    }
}

