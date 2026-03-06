package com.wallaceespindola.k8sbatchprocessor.batch;

import com.wallaceespindola.k8sbatchprocessor.domain.BankAccount;
import com.wallaceespindola.k8sbatchprocessor.dto.ProgressEvent;
import com.wallaceespindola.k8sbatchprocessor.repository.BankAccountRepository;
import com.wallaceespindola.k8sbatchprocessor.service.ProgressService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.batch.core.configuration.annotation.StepScope;
import org.springframework.batch.item.Chunk;
import org.springframework.batch.item.ItemWriter;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@StepScope
public class AccountItemWriter implements ItemWriter<BankAccount> {

    @Autowired
    private BankAccountRepository repository;

    @Autowired
    private ProgressService progressService;

    @Value("#{stepExecutionContext['podName']}")
    private String podName;

    @Value("#{stepExecutionContext['partitionId']}")
    private Integer partitionId;

    @Value("#{stepExecutionContext['total']}")
    private Long total;

    @Override
    public void write(Chunk<? extends BankAccount> chunk) {
        repository.saveAll(chunk.getItems());

        long processed = repository.countByPartitionIdAndStatus(partitionId, "PROCESSED");
        int percent = total > 0 ? (int) (processed * 100 / total) : 0;

        for (BankAccount account : chunk.getItems()) {
            log.debug("[{}] Wrote account {} (processed {}/{})", podName, account.getAccountNumber(), processed, total);

            ProgressEvent event = ProgressEvent.accountEvent(
                    account.getAccountNumber(),
                    podName,
                    partitionId,
                    processed,
                    total,
                    account.getProcessedAt()
            );
            progressService.broadcast(event);
        }
    }
}
