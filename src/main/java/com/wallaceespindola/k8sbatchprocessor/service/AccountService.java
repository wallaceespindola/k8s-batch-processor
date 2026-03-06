package com.wallaceespindola.k8sbatchprocessor.service;

import com.wallaceespindola.k8sbatchprocessor.domain.BankAccount;
import com.wallaceespindola.k8sbatchprocessor.dto.BatchStatus;
import com.wallaceespindola.k8sbatchprocessor.dto.PartitionStatus;
import com.wallaceespindola.k8sbatchprocessor.repository.BankAccountRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class AccountService {

    private final BankAccountRepository repository;

    @Transactional
    public List<BankAccount> generateAccounts(int count) {
        log.info("Generating {} bank accounts", count);
        repository.deleteAll();
        repository.flush();

        List<BankAccount> accounts = new ArrayList<>(count);
        for (int i = 1; i <= count; i++) {
            accounts.add(BankAccount.builder()
                    .accountNumber("Acc" + i)
                    .status("PENDING")
                    .createdAt(LocalDateTime.now())
                    .build());
        }
        List<BankAccount> saved = repository.saveAll(accounts);
        log.info("Generated {} accounts with IDs {} to {}", saved.size(),
                saved.getFirst().getId(), saved.getLast().getId());
        return saved;
    }

    @Transactional
    public void resetAll() {
        log.info("Resetting all bank accounts");
        repository.deleteAll();
    }

    public BatchStatus getCurrentStatus(String jobStatus, int podCount) {
        long total = repository.count();
        long processed = repository.countByStatus("PROCESSED");
        int overallPct = total > 0 ? (int) (processed * 100 / total) : 0;

        List<PartitionStatus> partitions = new ArrayList<>();
        if (podCount > 0) {
            for (int i = 1; i <= podCount; i++) {
                long partTotal = repository.countByPartitionId(i);
                long partProcessed = repository.countByPartitionIdAndStatus(i, "PROCESSED");
                int pct = partTotal > 0 ? (int) (partProcessed * 100 / partTotal) : 0;
                partitions.add(new PartitionStatus(i, "pod-" + i, partProcessed, partTotal, pct));
            }
        }

        return new BatchStatus(jobStatus, total, processed, podCount, overallPct, partitions, LocalDateTime.now());
    }
}
