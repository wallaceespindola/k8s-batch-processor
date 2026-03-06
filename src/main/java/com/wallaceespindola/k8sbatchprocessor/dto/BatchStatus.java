package com.wallaceespindola.k8sbatchprocessor.dto;

import io.swagger.v3.oas.annotations.media.Schema;

import java.time.LocalDateTime;
import java.util.List;

@Schema(description = "Overall batch job status")
public record BatchStatus(

    @Schema(description = "Current job status", example = "RUNNING")
    String jobStatus,

    @Schema(description = "Total accounts in the database", example = "100")
    long totalAccounts,

    @Schema(description = "Total processed accounts", example = "40")
    long processedAccounts,

    @Schema(description = "Number of pods used", example = "4")
    int podCount,

    @Schema(description = "Overall completion percentage", example = "40")
    int overallPercent,

    @Schema(description = "Per-partition status")
    List<PartitionStatus> partitions,

    @Schema(description = "Timestamp of this status snapshot")
    LocalDateTime timestamp
) {}
