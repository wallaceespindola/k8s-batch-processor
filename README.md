# K8s Batch Processor

<p align="center">
  <img src="docs/banner.svg" alt="K8s Batch Processor Banner" width="100%"/>
</p>

<p align="center">
  <a href="https://github.com/wallaceespindola/k8s-batch-processor/actions/workflows/build.yml">
    <img src="https://github.com/wallaceespindola/k8s-batch-processor/actions/workflows/build.yml/badge.svg" alt="Build & Test"/>
  </a>
  <a href="https://github.com/wallaceespindola/k8s-batch-processor/actions/workflows/codeql.yml">
    <img src="https://github.com/wallaceespindola/k8s-batch-processor/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"/>
  </a>
  <img src="https://img.shields.io/badge/Java-21-ED8B00?logo=openjdk&logoColor=white" alt="Java 21"/>
  <img src="https://img.shields.io/badge/Spring%20Boot-3.4.1-6DB33F?logo=springboot&logoColor=white" alt="Spring Boot 3.4.1"/>
  <img src="https://img.shields.io/badge/Spring%20Batch-5.2-6DB33F?logo=spring&logoColor=white" alt="Spring Batch 5"/>
  <img src="https://img.shields.io/badge/Kubernetes-HPA%20ready-326CE5?logo=kubernetes&logoColor=white" alt="Kubernetes"/>
  <img src="https://img.shields.io/badge/H2-in--memory-004088?logo=h2&logoColor=white" alt="H2"/>
  <img src="https://img.shields.io/badge/SSE-real--time-FF6B6B" alt="SSE"/>
  <a href="https://github.com/wallaceespindola/k8s-batch-processor/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License"/>
  </a>
</p>

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

There are **two completely separate ways** to run this application:

| Mode | What runs | Scripts used |
|---|---|---|
| **Local** | Plain `java -jar` on your machine, no containers | `run.sh` / `run.bat` / `run.ps1`, Maven, Docker Compose |
| **Kubernetes** | Docker image deployed to a K8s cluster via `kubectl` | `kubectl apply -f k8s/` |

The `run.sh`, `run.bat` and `run.ps1` scripts **do not start Kubernetes**. They simply build the JAR (if missing) and launch it as a regular Java process on port 8080 — exactly the same as `java -jar`.

---

## Running locally

### Prerequisites
- Java 21+
- Maven 3.9+

---

### Option 1 — Maven (any OS)

```bash
# Clone
git clone https://github.com/wallaceespindola/k8s-batch-processor.git
cd k8s-batch-processor

# Run in foreground (dev mode, hot-reload via DevTools)
mvn spring-boot:run

# Or: build JAR then run
mvn clean package -DskipTests
java -jar target/k8s-batch-processor-*.jar
```

Open the dashboard → **http://localhost:8080**

---

### Option 2 — Shell scripts (macOS / Linux)

The scripts build the JAR automatically if none is found, start the app in the background, and poll `/actuator/health` until the app is ready.

```bash
# Start
./run.sh

# Stop (graceful SIGTERM → SIGKILL after 20 s)
./stop.sh
```

Or via Make:

```bash
make run    # calls run.sh
make stop   # calls stop.sh
```

---

### Option 3 — Batch scripts (Windows cmd)

```cmd
:: Start
run.bat

:: Stop
stop.bat
```

Or via Make:

```cmd
make run-win
make stop-win
```

---

### Option 4 — PowerShell scripts (Windows PowerShell 5.1+)

```powershell
# Start
.\run.ps1

# Stop
.\stop.ps1
```

Or via Make:

```cmd
make run-ps
make stop-ps
```

> If PowerShell blocks unsigned scripts, run once:
> `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`
> The Makefile targets pass `-ExecutionPolicy Bypass` automatically.

---

### Option 5 — Docker Compose

```bash
docker-compose up --build -d   # build image + start
docker-compose logs -f          # follow logs
docker-compose down             # stop and remove containers
```

---

### Other Make targets

```bash
make dev           # mvn spring-boot:run (foreground, hot-reload)
make build         # mvn clean package -DskipTests
make test          # run all tests
make test-coverage # tests + JaCoCo HTML report
make lint          # Checkstyle
make clean         # mvn clean
make docker        # docker-compose up --build -d
make swagger       # open Swagger UI in browser
make h2            # open H2 console (auto-connects to batchdb)
make health        # curl actuator/health
make k8s-deploy    # kubectl apply -f k8s/
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
| `GET`  | `/h2.html` | H2 console (auto-connects with correct JDBC URL) |

### Start Request

```json
POST /api/batch/start
{
  "accountCount": 100,
  "podCount": 4,
  "processingDelayMs": 1000
}
```
`processingDelayMs` — simulated work time per account in milliseconds. Allowed values: `100`, `300`, `500`, `1000`, `1500`, `2000`. Default: `1000`.

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

## Running on Kubernetes

> This section requires Docker, `kubectl`, and a Kubernetes cluster (local or cloud).
> The scripts from the **Running locally** section above are **not used here** — Kubernetes runs the app inside containers managed by the cluster.

### Prerequisites

- A running Kubernetes cluster — local ([minikube](https://minikube.sigs.k8s.io/) or [kind](https://kind.sigs.k8s.io/)) or cloud (EKS / GKE / AKS)
- `kubectl` configured and pointing at your cluster
- Docker (to build and push the image)

---

### Step 1 — Start a local cluster (minikube example)

```bash
# Install minikube if needed: https://minikube.sigs.k8s.io/docs/start/
minikube start --cpus=4 --memory=4g

# Point Docker to minikube's registry so images don't need to be pushed
eval $(minikube docker-env)        # macOS/Linux
# minikube docker-env | Invoke-Expression   # Windows PowerShell
```

> **kind alternative**
> ```bash
> kind create cluster --name batch
> kubectl cluster-info --context kind-batch
> ```

---

### Step 2 — Build and push the Docker image

```bash
# Build the JAR first
mvn clean package -DskipTests

# Build the Docker image
docker build -t wallaceespindola/k8s-batch-processor:latest .

# If using a remote registry (DockerHub, ECR, GCR…)
docker push wallaceespindola/k8s-batch-processor:latest

# If using minikube's built-in registry (no push needed)
eval $(minikube docker-env)
docker build -t wallaceespindola/k8s-batch-processor:latest .
# Also set imagePullPolicy: Never in k8s/deployment.yaml for local images
```

---

### Step 3 — Deploy to the cluster

```bash
# Apply all manifests (Deployment + Services + HPA + ConfigMap)
kubectl apply -f k8s/

# Verify everything is running
kubectl get pods -l app=k8s-batch-processor
kubectl get svc  -l app=k8s-batch-processor
kubectl get hpa  k8s-batch-processor-hpa
```

Expected output:

```
NAME                                   READY   STATUS    RESTARTS   AGE
k8s-batch-processor-7d9f8b6c4d-xk2p9  1/1     Running   0          30s

NAME                              TYPE        CLUSTER-IP      PORT(S)
k8s-batch-processor               ClusterIP   10.96.0.1       80/TCP
k8s-batch-processor-nodeport      NodePort    10.96.0.2       80:30080/TCP

NAME                          REFERENCE                        TARGETS         MINPODS   MAXPODS
k8s-batch-processor-hpa       Deployment/k8s-batch-processor   cpu: 5%/60%     1         8
```

---

### Step 4 — Access the dashboard

```bash
# Option A: NodePort (port 30080 is fixed in service.yaml)
minikube ip                         # get cluster IP, e.g. 192.168.49.2
open http://192.168.49.2:30080      # open dashboard

# Option B: minikube service shortcut
minikube service k8s-batch-processor-nodeport

# Option C: port-forward (any cluster)
kubectl port-forward svc/k8s-batch-processor 8080:80
open http://localhost:8080
```

---

### Step 5 — Tear down

```bash
kubectl delete -f k8s/             # remove all resources
# minikube stop                    # pause cluster
# minikube delete                  # destroy cluster completely
```

Or via Make:

```bash
make k8s-deploy    # kubectl apply -f k8s/
make k8s-delete    # kubectl delete -f k8s/
make k8s-status    # kubectl get pods -l app=k8s-batch-processor
make k8s-logs      # kubectl logs -l app=k8s-batch-processor --tail=100 -f
```

---

### How "Number of Pods" maps to Kubernetes

This is the key design point of the POC — understanding the two layers of "pods":

#### Layer 1 — Kubernetes replicas (physical pods)

The `Deployment` starts with **1 replica** by default. The `HorizontalPodAutoscaler` watches CPU (≥ 60%) and memory (≥ 70%) metrics and scales the Deployment between **1 and 8 replicas** automatically:

```
┌─────────────────────────────────────────────────┐
│  Kubernetes Deployment: k8s-batch-processor      │
│                                                  │
│  replica-1 (pod)  replica-2 (pod)  ...          │
│  Spring Boot app  Spring Boot app                │
│  port 8080        port 8080                      │
└─────────────────────────────────────────────────┘
         ▲ scaled by HPA on CPU/memory load
```

#### Layer 2 — Spring Batch partitions (logical pods / threads)

When you click **Start** and set "Number of Pods = 4", that number travels as a `JobParameter` into the Spring Batch job. Inside the single application process, the `@JobScope` partitioned step creates **4 worker threads** — one per partition — each claiming an exclusive ID range of accounts:

```
POST /api/batch/start  { "podCount": 4, "accountCount": 100 }
         │
         ▼
BatchJobService.startJob()
  JobParameters: podCount=4, accountCount=100
         │
         ▼
AccountPartitioner.partition(gridSize=4)
  → partition-1: minId=1,  maxId=25,  podName=pod-1
  → partition-2: minId=26, maxId=50,  podName=pod-2
  → partition-3: minId=51, maxId=75,  podName=pod-3
  → partition-4: minId=76, maxId=100, podName=pod-4
         │
         ▼
ThreadPoolTaskExecutor (corePoolSize=4)
  Thread batch-pod-1  →  reads Acc1–Acc25   →  processes  →  writes + SSE
  Thread batch-pod-2  →  reads Acc26–Acc50  →  processes  →  writes + SSE  } parallel
  Thread batch-pod-3  →  reads Acc51–Acc75  →  processes  →  writes + SSE
  Thread batch-pod-4  →  reads Acc76–Acc100 →  processes  →  writes + SSE
```

#### How podCount flows through the code

```
UI select "4 pods"
  → fetch POST /api/batch/start { podCount: 4 }
    → BatchController → BatchJobService.startJob(request)
      → JobParameters.addLong("podCount", 4)
        → @JobScope partitionedStep reads #{jobParameters['podCount']}
          → ThreadPoolTaskExecutor(corePoolSize=4)
          → partitioner.partition(gridSize=4)
            → 4 ExecutionContexts with minId/maxId ranges
              → 4 worker threads each running their own reader/processor/writer
```

The `@JobScope` annotation is critical: it forces Spring to create a **new Step bean per job execution**, so the thread pool size and grid size are set dynamically at launch time, not at application startup.

#### POC vs production remote partitioning

| | This POC | Production (remote partitioning) |
|---|---|---|
| "Pods" | Threads inside one JVM | Actual Kubernetes pods (separate processes) |
| Partition coordination | `ThreadPoolTaskExecutor` | Kafka topics / HTTP / JMS |
| State sharing | Shared in-memory H2 | External PostgreSQL / Redis |
| Scaling | HPA scales the single app | HPA scales worker pods independently |
| Pod count | Chosen in UI → `JobParameter` | Equals number of running worker replicas |

In a remote-partitioning setup, you would deploy a **manager pod** (runs the partitioner, writes partitions to Kafka) and **N worker pods** (each consumes one Kafka partition and runs its own reader/processor/writer). The HPA would scale worker pods based on queue depth or CPU. This POC simulates that topology with threads, making the full flow observable in a single process without a cluster.

---

### HPA behaviour in detail

```yaml
# k8s/hpa.yaml
minReplicas: 1
maxReplicas: 8
metrics:
  - cpu    averageUtilization: 60   # scale up when avg CPU > 60 %
  - memory averageUtilization: 70   # scale up when avg memory > 70 %
scaleUp:   stabilizationWindow: 30s,  add up to 2 pods per 30 s
scaleDown: stabilizationWindow: 120s, remove 1 pod per 60 s
```

To trigger the HPA manually during testing, run several concurrent batch jobs or use a load generator:

```bash
# Watch HPA in real time
kubectl get hpa k8s-batch-processor-hpa -w

# Watch pods scale up/down
kubectl get pods -l app=k8s-batch-processor -w

# Generate CPU load with a tight loop (from another terminal)
kubectl run load --image=busybox --restart=Never -- \
  sh -c "while true; do wget -q -O- http://k8s-batch-processor/api/batch/health; done"
```

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
├── Makefile
├── run.sh / stop.sh          # macOS / Linux start-stop scripts
├── run.bat / stop.bat         # Windows cmd start-stop scripts
└── run.ps1 / stop.ps1         # Windows PowerShell start-stop scripts
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
