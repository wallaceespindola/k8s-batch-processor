package com.wallaceespindola.k8sbatchprocessor.service;

import com.wallaceespindola.k8sbatchprocessor.dto.BatchRequest;
import com.wallaceespindola.k8sbatchprocessor.dto.BatchStatus;
import com.wallaceespindola.k8sbatchprocessor.dto.ProgressEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.batch.core.*;
import org.springframework.batch.core.explore.JobExplorer;
import org.springframework.batch.core.launch.JobLauncher;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

@Slf4j
@Service
@RequiredArgsConstructor
public class BatchJobService {

    private final Job accountProcessingJob;
    private final JobLauncher jobLauncher;
    private final JobExplorer jobExplorer;
    private final AccountService accountService;
    private final ProgressService progressService;

    private final AtomicReference<String> currentStatus = new AtomicReference<>("IDLE");
    private final AtomicInteger currentPodCount = new AtomicInteger(0);

    @Async
    public void startJob(BatchRequest request) {
        if ("RUNNING".equals(currentStatus.get())) {
            log.warn("Job already running. Ignoring start request.");
            return;
        }

        try {
            currentStatus.set("RUNNING");
            currentPodCount.set(request.podCount());

            log.info("Starting batch job: {} accounts, {} pods", request.accountCount(), request.podCount());

            // Generate accounts first
            accountService.generateAccounts(request.accountCount());

            // Notify frontend that job is starting
            progressService.broadcast(ProgressEvent.startEvent(request.podCount(), request.accountCount()));

            // Launch the Spring Batch job with parameters
            JobParameters params = new JobParametersBuilder()
                    .addLong("podCount", (long) request.podCount())
                    .addLong("accountCount", (long) request.accountCount())
                    .addLong("timestamp", System.currentTimeMillis())
                    .toJobParameters();

            JobExecution execution = jobLauncher.run(accountProcessingJob, params);
            log.info("Job completed with status: {}", execution.getStatus());

            currentStatus.set(execution.getStatus().name());

        } catch (Exception e) {
            log.error("Job failed: {}", e.getMessage(), e);
            currentStatus.set("FAILED");
        }
    }

    public void reset() {
        currentStatus.set("IDLE");
        currentPodCount.set(0);
        accountService.resetAll();
        progressService.broadcast(ProgressEvent.resetEvent());
        log.info("Batch job reset completed");
    }

    public BatchStatus getStatus() {
        return accountService.getCurrentStatus(currentStatus.get(), currentPodCount.get());
    }

    public String getJobStatus() {
        return currentStatus.get();
    }

    public boolean isRunning() {
        return "RUNNING".equals(currentStatus.get());
    }
}
