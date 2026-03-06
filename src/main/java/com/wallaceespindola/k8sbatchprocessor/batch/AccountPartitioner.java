package com.wallaceespindola.k8sbatchprocessor.batch;

import com.wallaceespindola.k8sbatchprocessor.repository.BankAccountRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.batch.core.partition.support.Partitioner;
import org.springframework.batch.item.ExecutionContext;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class AccountPartitioner implements Partitioner {

    private final BankAccountRepository repository;

    @Override
    public Map<String, ExecutionContext> partition(int gridSize) {
        List<Long> ids = repository.findAllIdsSorted();
        int total = ids.size();

        if (total == 0) {
            log.warn("No accounts found to partition");
            return Map.of();
        }

        log.info("Partitioning {} accounts into {} partitions (pods)", total, gridSize);

        int perPartition = total / gridSize;
        int remainder = total % gridSize;

        Map<String, ExecutionContext> result = new LinkedHashMap<>();
        int startIndex = 0;

        for (int i = 0; i < gridSize; i++) {
            int partitionSize = perPartition + (i < remainder ? 1 : 0);
            if (partitionSize == 0) continue;

            int endIndex = startIndex + partitionSize;
            List<Long> partitionIds = ids.subList(startIndex, Math.min(endIndex, total));

            long minId = partitionIds.getFirst();
            long maxId = partitionIds.getLast();
            int partitionId = i + 1;

            ExecutionContext ctx = new ExecutionContext();
            ctx.putLong("minId", minId);
            ctx.putLong("maxId", maxId);
            ctx.putInt("partitionId", partitionId);
            ctx.put("podName", "pod-" + partitionId);
            ctx.putLong("total", partitionSize);

            result.put("partition" + partitionId, ctx);
            startIndex = endIndex;

            log.info("Partition {} (pod-{}): IDs {}-{}, {} accounts",
                    partitionId, partitionId, minId, maxId, partitionSize);
        }

        return result;
    }
}
