# Project Context: K8s Batch Processor

## What This Is

A Spring Boot 3 / Spring Batch 5 application that demonstrates Kubernetes-native parallel batch processing.
Users generate N bank accounts from a browser frontend, choose P pods, and watch each pod process its slice
in real time via Server-Sent Events (SSE).

## Core Flow

1. **User** enters account count (default 100) + pod count (default 4) in the web dashboard
2. `POST /api/batch/start` → `BatchJobService.startJob()` (async)
3. `AccountService.generateAccounts(N)` creates `BankAccount` rows with `status=PENDING`
4. SSE `start` event is broadcast to all connected browsers
5. Spring Batch `Job` launches with `JobParameters: podCount, accountCount, timestamp`
6. `@JobScope` `partitionedStep` reads `podCount` from job params, sets `gridSize`
7. `AccountPartitioner.partition(gridSize)` divides all account IDs into P ranges, each with `minId/maxId/partitionId/podName/total`
8. `ThreadPoolTaskExecutor` runs P partitions in parallel threads (`batch-pod-1..P`)
9. Each partition thread: `AccountItemReader` (reads by ID range) → `AccountItemProcessor` (`Thread.sleep(1000)`, sets status/podName/processedAt) → `AccountItemWriter` (saves + broadcasts SSE `account` event)
10. After job completes, `JobExecutionListenerSupport.afterJob()` broadcasts SSE `complete` event

## Key Design Choices

- **Single app, thread-based partitions**: Simulates multiple pods within one JVM. In real k8s, remote partitioning (via Kafka/AMQP) would dispatch work to separate pod replicas.
- **Chunk size = 1**: Ensures SSE events fire after every single account, giving real-time granularity.
- **`@JobScope` partitioned step**: Allows dynamic `gridSize` from `JobParameters['podCount']` — a new step bean is created per job execution.
- **H2 in-memory, `DB_CLOSE_DELAY=-1`**: Persists for app lifetime; Spring Batch's metadata schema is auto-initialized.
- **SSE over WebSocket**: Simpler for one-directional server→browser streaming; no broker needed.
- **`@Async` on `BatchJobService.startJob()`**: The REST endpoint returns 202 immediately; the batch job runs in a background thread.

## Entity: BankAccount

```
id (PK, auto), account_number, status (PENDING|PROCESSED), partition_id,
pod_name, processed_at, created_at
```

## SSE Event Types

| type     | When                        | Key fields                                           |
|----------|-----------------------------|------------------------------------------------------|
| start    | Job begins                  | podCount, totalAccounts                              |
| account  | Each account written        | accountNumber, podName, partitionId, processed, total |
| complete | Job finishes (afterJob)     | totalAccounts                                        |
| reset    | Reset endpoint called       | —                                                    |

## Endpoints

| Verb   | Path                  | Purpose                              |
|--------|-----------------------|--------------------------------------|
| POST   | /api/batch/start      | Start job (202 Accepted, async)      |
| GET    | /api/batch/status     | Poll current state                   |
| POST   | /api/batch/reset      | Delete accounts, IDLE state          |
| GET    | /api/batch/health     | Quick check                          |
| GET    | /api/sse/progress     | SSE stream (text/event-stream)       |
| GET    | /swagger-ui.html      | Swagger UI                           |
| GET    | /h2-console           | H2 database console                  |
| GET    | /actuator/health      | Spring Actuator health               |

## Files of Note

| File | Role |
|------|------|
| `BatchConfig.java` | Job/Step/Reader wiring; `@JobScope` on partitioned step |
| `AccountPartitioner.java` | Divides IDs into P ranges for P pods |
| `AccountItemProcessor.java` | `@StepScope`; sleeps 1s, stamps processed_at |
| `AccountItemWriter.java` | `@StepScope`; saves to DB, fires SSE via ProgressService |
| `BatchJobService.java` | `@Async` launcher; tracks RUNNING/IDLE/COMPLETED state |
| `ProgressService.java` | Manages `SseEmitter` list; broadcasts JSON events |
| `static/index.html` | Self-contained dashboard; vanilla JS + SSE + block progress bars |
| `k8s/hpa.yaml` | HPA scales 1–8 replicas on CPU ≥60% or memory ≥70% |

## Known Limitations / Future Work

- Single-app thread simulation vs. true k8s remote partitioning (would need Kafka + worker pods)
- H2 in-memory (lost on restart); replace with PostgreSQL for production
- No authentication on REST APIs
- `AtomicReference<String>` for job status is simplified; production should use Spring Batch JobRepository queries
- If app restarts mid-job, in-flight accounts remain PENDING (can re-run same job)

## Running

```bash
mvn spring-boot:run          # Local
make docker                   # Docker Compose
make k8s-deploy               # Kubernetes
open http://localhost:8080    # Dashboard
```
