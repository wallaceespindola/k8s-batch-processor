package com.wallaceespindola.k8sbatchprocessor.batch;

import com.wallaceespindola.k8sbatchprocessor.domain.BankAccount;
import com.wallaceespindola.k8sbatchprocessor.repository.BankAccountRepository;
import com.wallaceespindola.k8sbatchprocessor.service.AccountService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.batch.item.ExecutionContext;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class AccountPartitionerTest {

    @Autowired
    private AccountPartitioner partitioner;

    @Autowired
    private AccountService accountService;

    @Autowired
    private BankAccountRepository repository;

    @BeforeEach
    void setUp() {
        repository.deleteAll();
    }

    @Test
    void partition_creates_correct_number_of_partitions() {
        accountService.generateAccounts(12);
        Map<String, ExecutionContext> partitions = partitioner.partition(4);

        assertThat(partitions).hasSize(4);
    }

    @Test
    void partition_sets_partition_metadata() {
        accountService.generateAccounts(12);
        Map<String, ExecutionContext> partitions = partitioner.partition(3);

        for (Map.Entry<String, ExecutionContext> entry : partitions.entrySet()) {
            ExecutionContext ctx = entry.getValue();
            assertThat(ctx.containsKey("minId")).isTrue();
            assertThat(ctx.containsKey("maxId")).isTrue();
            assertThat(ctx.containsKey("partitionId")).isTrue();
            assertThat(ctx.containsKey("podName")).isTrue();
            assertThat(ctx.containsKey("total")).isTrue();
        }
    }

    @Test
    void partition_distributes_accounts_evenly() {
        accountService.generateAccounts(12);
        Map<String, ExecutionContext> partitions = partitioner.partition(4);

        long totalDistributed = partitions.values().stream()
                .mapToLong(ctx -> ctx.getLong("total"))
                .sum();

        assertThat(totalDistributed).isEqualTo(12);
    }

    @Test
    void partition_handles_uneven_distribution() {
        accountService.generateAccounts(10);
        Map<String, ExecutionContext> partitions = partitioner.partition(3); // 10/3 = 3 rem 1

        long totalDistributed = partitions.values().stream()
                .mapToLong(ctx -> ctx.getLong("total"))
                .sum();

        assertThat(totalDistributed).isEqualTo(10);
    }

    @Test
    void partition_assigns_pod_names() {
        accountService.generateAccounts(8);
        Map<String, ExecutionContext> partitions = partitioner.partition(2);

        assertThat(partitions).containsKey("partition1");
        assertThat(partitions).containsKey("partition2");
        assertThat(partitions.get("partition1").getString("podName")).isEqualTo("pod-1");
        assertThat(partitions.get("partition2").getString("podName")).isEqualTo("pod-2");
    }

    @Test
    void partition_empty_repository_returns_empty_map() {
        Map<String, ExecutionContext> partitions = partitioner.partition(4);
        assertThat(partitions).isEmpty();
    }
}
