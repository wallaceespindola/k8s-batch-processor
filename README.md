# K8s Batch Processor

A **Kubernetes-native Spring Batch application** that demonstrates distributed, parallelized batch processing with a real-time live dashboard.

Bank accounts are generated on demand, then distributed across configurable "pods" (Spring Batch partitions), each processing their slice in parallel. The frontend shows real-time progress via **Server-Sent Events**, with one block per account in each pod's progress bar.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Browser (HTML/CSS/JS)                  │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Control Panel: account count + pod count + start │   │
│  │  Live Progress: N progress bars (one per pod)     │   │
│  │  Each block = 1 bank account                      │   │
│  └──────────────────────────────────────────────────┘   │
│                    SSE (/api/sse/progress)                │
└───────────────────────┬─────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│              Spring Boot Application (8080)              │
│                                                          │
│  REST API  ─────────────────────────────────────────    │
│  POST /api/batch/start   → generate accounts + run job   │
│  GET  /api/batch/status  → current job + partition state  │
│  POST /api/batch/reset   → clear all data                │
│                                                          │
│  Spring Batch Job                                        │
│  ┌──────────────────────────────────────────────────┐   │
│  │  partitionedStep (gridSize = podCount)            │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐        │   │
│  │  │  pod-1   │  │  pod-2   │  │  pod-N   │  ...   │   │
│  │  │ Acc1-25  │  │ Acc26-50 │  │ AccX-Y   │        │   │
│  │  │ sleep 1s │  │ sleep 1s │  │ sleep 1s │        │   │
│  │  │ per acct │  │ per acct │  │ per acct │        │   │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘        │   │
│  │       └─────────────┴─────────────┘               │   │
│  │           After each write → SSE broadcast         │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  H2 In-Memory Database                                   │
│  bank_accounts (id, account_number, status, pod_name,    │
│                 partition_id, processed_at, created_at)  │
└─────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Concern | Solution |
|---|---|
| Parallelism | Spring Batch `@JobScope` partitioned step with `ThreadPoolTaskExecutor` |
| Dynamic pod count | `gridSize` injected from `JobParameters['podCount']` via `@JobScope` |
| Real-time updates | Spring `SseEmitter` — `AccountItemWriter` broadcasts after each account write |
| Processing simulation | `Thread.sleep(1000)` in `AccountItemProcessor` (1s per account) |
| State tracking | `BankAccount.status` + `podName` + `processedAt` written after processing |
| K8s scalability | HPA manifest scales replicas 1–8 based on CPU/memory |

---

## Tech Stack

- **Java 21** + **Spring Boot 3.4.1**
- **Spring Batch 5** — partitioned step, chunk-oriented processing
- **Spring Data JPA** + **H2** in-memory database
- **Spring Actuator** — health, metrics endpoints
- **springdoc-openapi 2.7** — Swagger UI
- **Spring DevTools** — hot reload in development
- **SSE** — real-time browser streaming (no WebSocket needed)
- **Docker** + **Docker Compose**
- **Kubernetes** manifests + **HPA**
- **GitHub Actions** — build, test, CodeQL
- **Dependabot** — automated dependency updates

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
