package com.wallaceespindola.k8sbatchprocessor.dto;

import io.swagger.v3.oas.annotations.media.Schema;

import java.time.LocalDateTime;

@Schema(description = "SSE progress event for a single processed account")
public record ProgressEvent(

    @Schema(description = "Event type: account | start | complete | reset")
    String type,

    @Schema(description = "Account number processed", example = "Acc42")
    String accountNumber,

    @Schema(description = "Pod name that processed this account", example = "pod-2")
    String podName,

    @Schema(description = "Partition identifier", example = "2")
    int partitionId,

    @Schema(description = "Processed accounts in this partition so far", example = "10")
    long processed,

    @Schema(description = "Total accounts in this partition", example = "25")
    long total,

    @Schema(description = "Percentage complete for this partition", example = "40")
    int percent,

    @Schema(description = "Timestamp of processing")
    LocalDateTime processedAt,

    @Schema(description = "Total pod count (in start event)")
    int podCount,

    @Schema(description = "Total account count (in start/complete events)")
    long totalAccounts
) {
    /** Factory for account-processed events */
    public static ProgressEvent accountEvent(String accountNumber, String podName, int partitionId,
                                              long processed, long total, LocalDateTime processedAt) {
        int pct = total > 0 ? (int) (processed * 100 / total) : 0;
        return new ProgressEvent("account", accountNumber, podName, partitionId,
                processed, total, pct, processedAt, 0, 0);
    }

    /** Factory for job-start events */
    public static ProgressEvent startEvent(int podCount, long totalAccounts) {
        return new ProgressEvent("start", null, null, 0, 0, 0, 0, null, podCount, totalAccounts);
    }

    /** Factory for job-complete events */
    public static ProgressEvent completeEvent(long totalAccounts) {
        return new ProgressEvent("complete", null, null, 0, totalAccounts, totalAccounts, 100,
                LocalDateTime.now(), 0, totalAccounts);
    }

    /** Factory for reset events */
    public static ProgressEvent resetEvent() {
        return new ProgressEvent("reset", null, null, 0, 0, 0, 0, null, 0, 0);
    }
}
