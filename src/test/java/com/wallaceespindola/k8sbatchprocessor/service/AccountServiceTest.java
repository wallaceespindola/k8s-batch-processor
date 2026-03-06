package com.wallaceespindola.k8sbatchprocessor.service;

import com.wallaceespindola.k8sbatchprocessor.domain.BankAccount;
import com.wallaceespindola.k8sbatchprocessor.repository.BankAccountRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class AccountServiceTest {

    @Autowired
    private AccountService accountService;

    @Autowired
    private BankAccountRepository repository;

    @BeforeEach
    void setUp() {
        repository.deleteAll();
    }

    @Test
    void generateAccounts_createsCorrectCount() {
        List<BankAccount> accounts = accountService.generateAccounts(10);

        assertThat(accounts).hasSize(10);
        assertThat(repository.count()).isEqualTo(10);
    }

    @Test
    void generateAccounts_setsCorrectAccountNumbers() {
        accountService.generateAccounts(5);

        List<BankAccount> all = repository.findAll();
        List<String> numbers = all.stream().map(BankAccount::getAccountNumber).sorted().toList();
        assertThat(numbers).containsExactly("Acc1", "Acc2", "Acc3", "Acc4", "Acc5");
    }

    @Test
    void generateAccounts_setsStatusPending() {
        accountService.generateAccounts(5);

        assertThat(repository.countByStatus("PENDING")).isEqualTo(5);
        assertThat(repository.countByStatus("PROCESSED")).isZero();
    }

    @Test
    void generateAccounts_clearsExistingAccounts() {
        accountService.generateAccounts(5);
        accountService.generateAccounts(3); // re-generate with fewer

        assertThat(repository.count()).isEqualTo(3);
    }

    @Test
    void resetAll_deletesAllAccounts() {
        accountService.generateAccounts(10);
        accountService.resetAll();

        assertThat(repository.count()).isZero();
    }

    @Test
    void getCurrentStatus_returnsCorrectTotals() {
        accountService.generateAccounts(10);
        var status = accountService.getCurrentStatus("IDLE", 0);

        assertThat(status.totalAccounts()).isEqualTo(10);
        assertThat(status.processedAccounts()).isZero();
        assertThat(status.jobStatus()).isEqualTo("IDLE");
    }
}
