package com.wallaceespindola.k8sbatchprocessor.dto;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(description = "Processing status of a single partition/pod")
public record PartitionStatus(

    @Schema(description = "Partition identifier", example = "1")
    int partitionId,

    @Schema(description = "Pod name processing this partition", example = "pod-1")
    String podName,

    @Schema(description = "Number of accounts processed so far", example = "15")
    long processed,

    @Schema(description = "Total accounts in this partition", example = "25")
    long total,

    @Schema(description = "Percentage complete (0-100)", example = "60")
    int percent
) {}
