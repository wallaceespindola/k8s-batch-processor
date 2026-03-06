# K8s Batch Processor

A **Kubernetes-native Spring Batch application** that demonstrates distributed, parallelized batch processing with a real-time live dashboard.

Bank accounts are generated on demand, then distributed across configurable "pods" (Spring Batch partitions), each processing their slice in parallel. The frontend shows real-time progress via **Server-Sent Events**, with one block per account in each pod's progress bar.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Browser (HTML/CSS/JS)                  │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Control Panel: account count + pod count + start │   │
│  │ Live Progress: N progress bars (one per pod)     │   │
│  │ Each block = 1 bank account                      │   │
│  └──────────────────────────────────────────────────┘   │
│                  SSE (/api/sse/progress)                │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│              Spring Boot Application (8080)             │
│                                                         │
│  REST API  ───────────────────────────────────────────  │
│  POST /api/batch/start  → generate accounts + run job   │
│  GET  /api/batch/status → current job + partition state │
│  POST /api/batch/reset  → clear all data                │
│                                                         │
│  Spring Batch Job                                       │
│  ┌──────────────────────────────────────────────────┐   │
│  │  partitionedStep (gridSize = podCount)           │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐        │   │
│  │  │  pod-1   │  │  pod-2   │  │  pod-N   │  ...   │   │
│  │  │ Acc1-25  │  │ Acc26-50 │  │ AccX-Y   │        │   │
│  │  │ sleep 1s │  │ sleep 1s │  │ sleep 1s │        │   │
│  │  │ per acct │  │ per acct │  │ per acct │        │   │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘        │   │
│  │       └─────────────┴─────────────┘              │   │
│  │         After each write → SSE broadcast         │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  H2 In-Memory Database                                  │
│  bank_accounts (id, account_number, status, pod_name,   │
│                 partition_id, processed_at, created_at) │
└─────────────────────────────────────────────────────────┘
```

### Parallelization Strategy — How Pods Consume Accounts

The core of this application is **Spring Batch local partitioning** with a thread-per-pod model. Here is the full sequence:

#### 1. Account Generation
When the user clicks **Start**, the backend generates N `BankAccount` rows in H2 with `status = PENDING`. Each row gets an auto-incremented `id` (e.g., 1 to 100 for 100 accounts).

#### 2. Partitioning — Dividing the Load
`AccountPartitioner` implements Spring Batch's `Partitioner` interface. It is called with `gridSize = podCount` (the number chosen by the user). It:
- Fetches all account IDs from the database (sorted ascending)
- Divides them into P contiguous ID ranges, distributing any remainder across the first partitions

```
100 accounts, 4 pods:
  pod-1 → IDs  1–25   (25 accounts)
  pod-2 → IDs 26–50   (25 accounts)
  pod-3 → IDs 51–75   (25 accounts)
  pod-4 → IDs 76–100  (25 accounts)

101 accounts, 4 pods (remainder = 1):
  pod-1 → IDs  1–26   (26 accounts)  ← gets the extra
  pod-2 → IDs 27–51   (25 accounts)
  pod-3 → IDs 52–76   (25 accounts)
  pod-4 → IDs 77–101  (25 accounts)
```

Each partition produces an `ExecutionContext` carrying `minId`, `maxId`, `partitionId`, `podName`, and `total`.

#### 3. Dynamic Grid Size via `@JobScope`
The partitioned step is annotated `@JobScope`, which means Spring creates a **new Step bean instance per job execution**. This allows injecting `podCount` directly from `JobParameters`:

```java
@Bean
@JobScope
public Step partitionedStep(...,
    @Value("#{jobParameters['podCount']}") Long podCount) {
    // gridSize set at runtime, not at application startup
    return new StepBuilder(...)
        .partitioner(workerStep.getName(), partitioner)
        .gridSize(podCount.intValue())
        .taskExecutor(executor)   // pool size = podCount
        .build();
}
```

#### 4. Parallel Execution — `ThreadPoolTaskExecutor`
A `ThreadPoolTaskExecutor` with `corePoolSize = podCount` is created fresh per job. Spring Batch dispatches each `ExecutionContext` to a separate thread, so all P partitions run **simultaneously**:

```
Thread batch-pod-1 → reads Acc1–Acc25   → processes → writes
Thread batch-pod-2 → reads Acc26–Acc50  → processes → writes   } all at once
Thread batch-pod-3 → reads Acc51–Acc75  → processes → writes
Thread batch-pod-4 → reads Acc76–Acc100 → processes → writes
```

#### 5. Per-Pod Processing — Chunk Size 1
Each worker thread runs a chunk-oriented step with **chunk size = 1**:
- **Reader** (`@StepScope` `RepositoryItemReader`): reads accounts from its `minId–maxId` range with `status = PENDING`, one at a time
- **Processor** (`@StepScope`): sleeps 1 second (simulating real work), then stamps `status = PROCESSED`, `processedAt = now()`, and `podName`
- **Writer** (`@StepScope`): persists the account, then queries the count of processed accounts for this partition and fires an **SSE event** to all connected browsers

Chunk size 1 ensures every single account triggers an immediate DB write and SSE broadcast, giving the frontend a live, per-account update.

#### 6. Real-Time Progress via SSE
`ProgressService` maintains a `CopyOnWriteArrayList<SseEmitter>`. After each write, `AccountItemWriter` calls `progressService.broadcast(event)`, which sends a JSON event to every connected browser tab:

```json
{ "type": "account", "accountNumber": "Acc42", "podName": "pod-2",
  "partitionId": 2, "processed": 10, "total": 25, "percent": 40,
  "processedAt": "2025-01-15T10:30:45" }
```

The browser updates the relevant pod's progress bar block-by-block, with no polling.

#### 7. Kubernetes Auto-Scaling (HPA)
In a real Kubernetes deployment, the `HorizontalPodAutoscaler` scales the application's replica count between 1 and 8 based on CPU (≥ 60%) and memory (≥ 70%) utilization. Combined with Spring Batch remote partitioning (e.g., via Kafka or HTTP), each pod replica would claim and process its own partition independently — exactly the same logical model, but across physical machines.

### Key Design Decisions

| Concern | Decision |
|---|---|
| Parallelism model | Spring Batch `@JobScope` partitioned step + `ThreadPoolTaskExecutor` (one thread = one pod) |
| Dynamic pod count | `gridSize` read from `JobParameters['podCount']` at job-launch time via `@JobScope` |
| Partition algorithm | Contiguous ID ranges; remainder distributed round-robin to first partitions |
| Chunk size | 1 — every account triggers an immediate DB commit + SSE push |
| Real-time streaming | `SseEmitter` (Server-Sent Events) — simpler than WebSocket for one-directional push |
| State durability | `BankAccount.podName` + `partitionId` + `processedAt` persisted at write time |
| K8s scalability | HPA scales replicas 1–8 on CPU/memory; remote partitioning path for true multi-pod |

---

## Tech Stack

### Backend
| Technology | Version | Role |
|---|---|---|
| Java | 21 (LTS) | Language — virtual threads ready, records, sealed classes |
| Spring Boot | 3.4.1 | Application framework, auto-configuration, embedded Tomcat |
| Spring Batch | 5.2 (via Boot) | Partitioned step, chunk-oriented processing, job repository |
| Spring Data JPA | 3.4 (via Boot) | ORM, `RepositoryItemReader`, derived queries |
| Spring Web MVC | 6.2 (via Boot) | REST controllers, `SseEmitter` for streaming |
| Spring Actuator | 3.4 (via Boot) | `/actuator/health`, `/actuator/metrics`, readiness/liveness probes |
| Spring DevTools | 3.4 (via Boot) | Hot reload during development |
| H2 Database | 2.x | In-memory relational DB — Spring Batch schema + app data |
| Hibernate | 6.6 (via Boot) | JPA provider, DDL auto-creation |
| Lombok | latest | `@Slf4j`, `@Builder`, `@RequiredArgsConstructor` boilerplate reduction |
| springdoc-openapi | 2.7.0 | Swagger UI + OpenAPI 3 spec generation |
| Jakarta Validation | 3.1 (via Boot) | `@Min`/`@Max` on request DTOs |
| JaCoCo | 0.8.12 | Test coverage reporting |

### Frontend
| Technology | Role |
|---|---|
| HTML5 / CSS3 / Vanilla JS | Self-contained dashboard (`static/index.html`) — no build step |
| Server-Sent Events (SSE) | One-directional real-time push from server to browser |
| CSS Custom Properties | Dark theme, pod-specific color palette |
| Fetch API | REST calls to start/reset the job |

### Infrastructure & CI/CD
| Technology | Role |
|---|---|
| Docker | Multi-stage build image (builder: JDK 21, runtime: JRE 21 Alpine) |
| Docker Compose | Single-service local stack |
| Kubernetes | Deployment, ClusterIP/NodePort service, HPA (auto-scale 1–8 replicas) |
| GitHub Actions | Build + test pipeline, Docker image build verification |
| CodeQL | Static security analysis on every push to `main` |
| Dependabot | Weekly automated dependency updates (Maven, Docker, GitHub Actions) |
| Maven | Build tool, Surefire (tests), JaCoCo (coverage) |

---

## Quick Start

### Prerequisites
- Java 21+
- Maven 3.9+

### Run locally

```bash
# Clone
git clone https://github.com/wallaceespindola/k8s-batch-processor.git
cd k8s-batch-processor

# Build and run
mvn spring-boot:run

# Open the dashboard
open http://localhost:8080
```

### With Docker

```bash
# Build and start
docker-compose up --build -d

# View logs
docker-compose logs -f

# Stop
docker-compose down
```

### With Make

```bash
make dev           # Run locally
make test          # Run tests
make test-coverage # Tests + JaCoCo coverage
make docker        # Docker Compose up
make swagger       # Open Swagger UI
make k8s-deploy    # Deploy to Kubernetes
```

---

## Usage

1. Open **http://localhost:8080**
2. Set **Account Count** (default 100, max 10,000)
3. Set **Number of Pods** (1–8, default 4)
4. Click **▶ Start Processing**
5. Watch real-time progress bars — each block turns colored when that account is processed
6. Click **↺ Reset** to clear state and start fresh

---

## API Reference

Swagger UI: **http://localhost:8080/swagger-ui.html**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/batch/start` | Start a batch job |
| `GET`  | `/api/batch/status` | Current job + partition status |
| `POST` | `/api/batch/reset` | Reset all data |
| `GET`  | `/api/batch/health` | Quick health check |
| `GET`  | `/api/sse/progress` | SSE stream (text/event-stream) |
| `GET`  | `/actuator/health` | Spring Actuator health |
| `GET`  | `/h2-console` | H2 database console |

### Start Request

```json
POST /api/batch/start
{
  "accountCount": 100,
  "podCount": 4
}
```

### SSE Event Format

```json
// Account processed
{"type":"account","accountNumber":"Acc42","podName":"pod-2","partitionId":2,
 "processed":17,"total":25,"percent":68,"processedAt":"2025-01-15T10:30:45"}

// Job started
{"type":"start","podCount":4,"totalAccounts":100}

// Job completed
{"type":"complete","totalAccounts":100}

// Reset
{"type":"reset"}
```

---

## Kubernetes Deployment

```bash
# Build and push Docker image
docker build -t wallaceespindola/k8s-batch-processor:latest .
docker push wallaceespindola/k8s-batch-processor:latest

# Deploy to cluster
kubectl apply -f k8s/

# Check pods
kubectl get pods -l app=k8s-batch-processor

# View logs
kubectl logs -l app=k8s-batch-processor -f

# HPA will auto-scale between 1-8 replicas based on CPU/memory
kubectl get hpa k8s-batch-processor-hpa
```

The HPA scales the number of application replicas. In a production setup with remote partitioning (e.g., via Kafka), each replica would be an independent worker pod. In this POC, the single replica uses thread-based partitioning to simulate N pods within one process.

---

## Running Tests

```bash
mvn test                                          # All tests
mvn test -Dtest=AccountServiceTest                # Single class
mvn test -Dtest=AccountPartitionerTest#partition_assigns_pod_names  # Single method
mvn verify                                        # Tests + coverage
```

---

## Project Structure

```
k8s-batch-processor/
├── src/main/java/com/wallaceespindola/k8sbatchprocessor/
│   ├── K8sBatchProcessorApplication.java
│   ├── batch/
│   │   ├── AccountItemProcessor.java  # sleep(1s), set status=PROCESSED
│   │   ├── AccountItemWriter.java     # persist + broadcast SSE
│   │   └── AccountPartitioner.java   # divide accounts into N partitions
│   ├── config/
│   │   ├── BatchConfig.java           # Job, Steps, Reader wiring
│   │   └── OpenApiConfig.java
│   ├── controller/
│   │   ├── BatchController.java       # REST API
│   │   └── SseController.java         # SSE endpoint
│   ├── domain/
│   │   └── BankAccount.java
│   ├── dto/
│   │   ├── BatchRequest.java
│   │   ├── BatchStatus.java
│   │   ├── PartitionStatus.java
│   │   └── ProgressEvent.java
│   ├── repository/
│   │   └── BankAccountRepository.java
│   └── service/
│       ├── AccountService.java        # generate/reset accounts
│       ├── BatchJobService.java       # launch/track jobs
│       └── ProgressService.java       # SSE emitter management
├── src/main/resources/
│   ├── application.yml
│   └── static/index.html             # Live dashboard
├── src/test/
├── k8s/                              # Kubernetes manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── hpa.yaml
│   └── configmap.yaml
├── .github/
│   ├── workflows/build.yml
│   ├── workflows/codeql.yml
│   └── dependabot.yml
├── Dockerfile
├── docker-compose.yml
└── Makefile
```

---

## Author

**Wallace Espindola**
- GitHub: [@wallaceespindola](https://github.com/wallaceespindola)
- Email: wallace.espindola@gmail.com
- LinkedIn: [wallaceespindola](https://www.linkedin.com/in/wallaceespindola/)

---

## License

Apache License 2.0 — see [LICENSE](LICENSE)
