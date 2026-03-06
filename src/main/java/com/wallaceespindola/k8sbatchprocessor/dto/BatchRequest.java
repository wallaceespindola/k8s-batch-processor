package com.wallaceespindola.k8sbatchprocessor.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

@Schema(description = "Request to start a batch processing job")
public record BatchRequest(

    @Schema(description = "Number of bank accounts to generate and process", example = "100", defaultValue = "100")
    @Min(value = 1, message = "Account count must be at least 1")
    @Max(value = 10000, message = "Account count must not exceed 10000")
    int accountCount,

    @Schema(description = "Number of pods (partitions) to use for parallel processing", example = "4", defaultValue = "4")
    @Min(value = 1, message = "Pod count must be at least 1")
    @Max(value = 8, message = "Pod count must not exceed 8")
    int podCount,

    @Schema(description = "Processing delay per account in milliseconds (100, 300, 500, 1000, 1500, 2000)", example = "1000", defaultValue = "1000")
    @Min(value = 100, message = "Processing delay must be at least 100ms")
    @Max(value = 2000, message = "Processing delay must not exceed 2000ms")
    int processingDelayMs
) {}
