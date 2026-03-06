package com.wallaceespindola.k8sbatchprocessor.batch;

import com.wallaceespindola.k8sbatchprocessor.domain.BankAccount;
import lombok.extern.slf4j.Slf4j;
import org.springframework.batch.core.configuration.annotation.StepScope;
import org.springframework.batch.item.ItemProcessor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;

@Slf4j
@Component
@StepScope
public class AccountItemProcessor implements ItemProcessor<BankAccount, BankAccount> {

    @Value("#{stepExecutionContext['podName']}")
    private String podName;

    @Value("#{stepExecutionContext['partitionId']}")
    private Integer partitionId;

    @Override
    public BankAccount process(BankAccount account) throws Exception {
        log.debug("[{}] Processing account: {}", podName, account.getAccountNumber());

        // Simulate backend processing time (1 second per account)
        Thread.sleep(1000);

        account.setStatus("PROCESSED");
        account.setPodName(podName);
        account.setPartitionId(partitionId);
        account.setProcessedAt(LocalDateTime.now());

        log.debug("[{}] Completed account: {} at {}", podName, account.getAccountNumber(), account.getProcessedAt());
        return account;
    }
}
