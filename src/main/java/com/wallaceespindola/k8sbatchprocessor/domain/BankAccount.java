package com.wallaceespindola.k8sbatchprocessor.domain;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Table(name = "bank_accounts", indexes = {
    @Index(name = "idx_status", columnList = "status"),
    @Index(name = "idx_partition_id", columnList = "partition_id")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class BankAccount {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "account_number", nullable = false, unique = true, length = 50)
    private String accountNumber;

    @Column(name = "status", nullable = false, length = 20)
    @Builder.Default
    private String status = "PENDING";

    @Column(name = "partition_id")
    private Integer partitionId;

    @Column(name = "pod_name", length = 50)
    private String podName;

    @Column(name = "processed_at")
    private LocalDateTime processedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    @Builder.Default
    private LocalDateTime createdAt = LocalDateTime.now();
}
