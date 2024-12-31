package com.example;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.amazonaws.xray.AWSXRayRecorder;
import com.amazonaws.xray.AWSXRayRecorderBuilder;
import com.amazonaws.xray.entities.Segment;
import com.amazonaws.xray.entities.Subsegment;

import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.Bucket;
import software.amazon.awssdk.services.s3.model.ListBucketsRequest;

import java.util.List;
import java.util.stream.Collectors;

@SpringBootApplication
@RestController
public class MainApplication {

    private final S3Client s3Client;
    private final AWSXRayRecorder xrayRecorder;

    public MainApplication() {
        xrayRecorder = AWSXRayRecorderBuilder.defaultRecorder();
        // Create the S3 client
        s3Client = S3Client.create();
    }

    public static void main(String[] args) {
        SpringApplication.run(MainApplication.class, args);
    }

    @GetMapping("/generate-manual-traces")
    public List<String> listBuckets() {
        // Start the parent segment
        Segment parentSegment = xrayRecorder.beginSegment("ManualTraceHandler");
        parentSegment.putAnnotation("HandlerType", "Manual");

        List<String> buckets = null;

        try {
            Subsegment s3SubSeg1 = xrayRecorder.beginSubsegment("S3ListBucketsCall1");
            s3SubSeg1.putAnnotation("Operation", "listBuckets1");

            try {
                buckets = s3Client.listBuckets(ListBucketsRequest.builder().build())
                                  .buckets()
                                  .stream()
                                  .map(Bucket::name)
                                  .collect(Collectors.toList());

                Subsegment extractSubSeg = xrayRecorder.beginSubsegment("ExtractFirstBucketName");
                try {
                    String firstBucketName = buckets.get(0);
                    extractSubSeg.putAnnotation("FirstBucketName", firstBucketName);
                } catch (Exception e) {
                    extractSubSeg.addException(e);
                    throw e;
                } finally {
                    xrayRecorder.endSubsegment(); // End "ExtractFirstBucketName"
                }

            } catch (Exception e) {
                s3SubSeg1.addException(e);
                throw e;
            } finally {
                xrayRecorder.endSubsegment(); // End "S3ListBucketsCall1"
            }


            // Create a sibling subsegment
            Subsegment s3SubSeg2 = xrayRecorder.beginSubsegment("S3ListBucketsCall2");
            s3SubSeg2.putAnnotation("Operation", "listBuckets2");

            try {
                s3Client.listBuckets(ListBucketsRequest.builder().build());
            } catch (Exception e) {
                s3SubSeg2.addException(e);
                throw e;
            } finally {
                xrayRecorder.endSubsegment(); // End "S3ListBucketsCall2"
            }

            return buckets; // Return the list of buckets

        } catch (Exception e) {
            parentSegment.addException(e);
            throw new RuntimeException("Failed to list S3 buckets: " + e.getMessage());
        } finally {
            xrayRecorder.endSegment(); // End "ManualTraceHandler"
        }
    }
}

