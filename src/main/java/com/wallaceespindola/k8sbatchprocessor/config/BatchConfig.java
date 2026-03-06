package com.wallaceespindola.k8sbatchprocessor.config;

import com.wallaceespindola.k8sbatchprocessor.batch.AccountItemProcessor;
import com.wallaceespindola.k8sbatchprocessor.batch.AccountItemWriter;
import com.wallaceespindola.k8sbatchprocessor.batch.AccountPartitioner;
import com.wallaceespindola.k8sbatchprocessor.domain.BankAccount;
import com.wallaceespindola.k8sbatchprocessor.dto.ProgressEvent;
import com.wallaceespindola.k8sbatchprocessor.repository.BankAccountRepository;
import com.wallaceespindola.k8sbatchprocessor.service.ProgressService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.batch.core.Job;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.configuration.annotation.JobScope;
import org.springframework.batch.core.configuration.annotation.StepScope;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.launch.support.RunIdIncrementer;
import org.springframework.batch.core.listener.JobExecutionListenerSupport;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.item.data.RepositoryItemReader;
import org.springframework.batch.item.data.builder.RepositoryItemReaderBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.domain.Sort;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import org.springframework.transaction.PlatformTransactionManager;

import java.util.List;
import java.util.Map;

@Slf4j
@Configuration
public class BatchConfig {

    @Bean
    public Job accountProcessingJob(JobRepository jobRepository,
                                    Step partitionedStep,
                                    ProgressService progressService,
                                    BankAccountRepository accountRepository) {
        return new JobBuilder("accountProcessingJob", jobRepository)
                .incrementer(new RunIdIncrementer())
                .listener(new JobExecutionListenerSupport() {
                    @Override
                    public void afterJob(org.springframework.batch.core.JobExecution jobExecution) {
                        long total = accountRepository.count();
                        log.info("Job {} finished with status: {}", jobExecution.getJobId(), jobExecution.getStatus());
                        progressService.broadcast(ProgressEvent.completeEvent(total));
                    }
                })
                .start(partitionedStep)
                .build();
    }

    /**
     * Job-scoped partitioned step — a new instance is created per job execution,
     * allowing dynamic podCount from job parameters.
     */
    @Bean
    @JobScope
    public Step partitionedStep(JobRepository jobRepository,
                                Step workerStep,
                                AccountPartitioner partitioner,
                                @Value("#{jobParameters['podCount']}") Long podCount) {

        int pods = (podCount != null) ? podCount.intValue() : 4;

        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(pods);
        executor.setMaxPoolSize(pods);
        executor.setThreadNamePrefix("batch-pod-");
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.afterPropertiesSet();

        log.info("Creating partitioned step with {} pods (grid size)", pods);

        return new StepBuilder("partitionedStep", jobRepository)
                .partitioner(workerStep.getName(), partitioner)
                .step(workerStep)
                .gridSize(pods)
                .taskExecutor(executor)
                .build();
    }

    @Bean
    public Step workerStep(JobRepository jobRepository,
                           PlatformTransactionManager transactionManager,
                           RepositoryItemReader<BankAccount> accountReader,
                           AccountItemProcessor accountProcessor,
                           AccountItemWriter accountWriter) {
        return new StepBuilder("workerStep", jobRepository)
                .<BankAccount, BankAccount>chunk(1, transactionManager)
                .reader(accountReader)
                .processor(accountProcessor)
                .writer(accountWriter)
                .build();
    }

    @Bean
    @StepScope
    public RepositoryItemReader<BankAccount> accountReader(
            BankAccountRepository repository,
            @Value("#{stepExecutionContext['minId']}") Long minId,
            @Value("#{stepExecutionContext['maxId']}") Long maxId,
            @Value("#{stepExecutionContext['total']}") Long total) {

        // Use findByIdBetweenOrderByIdAsc (no status filter) so pages stay stable
        // as items change from PENDING→PROCESSED during iteration.
        int pageSize = total != null ? total.intValue() : 100;

        return new RepositoryItemReaderBuilder<BankAccount>()
                .name("accountReader")
                .repository(repository)
                .methodName("findByIdBetween")
                .arguments(List.of(minId, maxId))
                .sorts(Map.of("id", Sort.Direction.ASC))
                .pageSize(pageSize)
                .build();
    }
}
