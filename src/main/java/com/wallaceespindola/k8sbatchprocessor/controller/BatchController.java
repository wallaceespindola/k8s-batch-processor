package com.wallaceespindola.k8sbatchprocessor.controller;

import com.wallaceespindola.k8sbatchprocessor.dto.BatchRequest;
import com.wallaceespindola.k8sbatchprocessor.dto.BatchStatus;
import com.wallaceespindola.k8sbatchprocessor.service.BatchJobService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api/batch")
@RequiredArgsConstructor
@Tag(name = "Batch Processing", description = "APIs to control the batch processing job")
@CrossOrigin(origins = "*")
public class BatchController {

    private final BatchJobService batchJobService;

    @PostMapping("/start")
    @Operation(summary = "Start a batch job", description = "Generates accounts and starts parallel batch processing across pods")
    public ResponseEntity<Map<String, Object>> start(@Valid @RequestBody BatchRequest request) {
        if (batchJobService.isRunning()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "A job is already running. Please wait or reset.",
                    "timestamp", LocalDateTime.now().toString()
            ));
        }

        log.info("Received start request: {} accounts, {} pods", request.accountCount(), request.podCount());
        batchJobService.startJob(request);

        return ResponseEntity.accepted().body(Map.of(
                "message", "Batch job started",
                "accountCount", request.accountCount(),
                "podCount", request.podCount(),
                "timestamp", LocalDateTime.now().toString()
        ));
    }

    @GetMapping("/status")
    @Operation(summary = "Get batch job status", description = "Returns current status of the batch job and per-partition progress")
    public ResponseEntity<BatchStatus> status() {
        return ResponseEntity.ok(batchJobService.getStatus());
    }

    @PostMapping("/reset")
    @Operation(summary = "Reset batch state", description = "Deletes all accounts and resets the job to IDLE state")
    public ResponseEntity<Map<String, Object>> reset() {
        if (batchJobService.isRunning()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Cannot reset while a job is running.",
                    "timestamp", LocalDateTime.now().toString()
            ));
        }

        batchJobService.reset();
        return ResponseEntity.ok(Map.of(
                "message", "Reset successful",
                "timestamp", LocalDateTime.now().toString()
        ));
    }

    @GetMapping("/health")
    @Operation(summary = "Batch controller health", description = "Lightweight health check for the batch API")
    public ResponseEntity<Map<String, Object>> health() {
        return ResponseEntity.ok(Map.of(
                "status", "UP",
                "jobStatus", batchJobService.getJobStatus(),
                "timestamp", LocalDateTime.now().toString()
        ));
    }
}
