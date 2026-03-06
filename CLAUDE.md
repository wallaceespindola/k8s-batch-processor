# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**k8s-batch-processor** is a Java/Spring Boot application for Kubernetes-native batch job processing. It is designed to run as a containerized batch workload orchestrated by Kubernetes Jobs or CronJobs.

## Core Stack

- **Java 21+**, Spring Boot (latest stable), Maven
- **Spring Batch** for job orchestration and step management
- **Spring Data JPA** + H2 (dev) / PostgreSQL (prod)
- **Spring Boot Actuator** for health and metrics endpoints
- **Kafka** for event-driven job triggering and result publishing
- **Docker** + Kubernetes manifests for deployment

## Build & Development Commands

```bash
# Build the project
mvn clean install

# Run locally
mvn spring-boot:run

# Run tests
mvn test

# Run a single test class
mvn test -Dtest=MyServiceTest

# Run a single test method
mvn test -Dtest=MyServiceTest#myMethod

# Package without tests
mvn package -DskipTests

# Build Docker image
docker build -t k8s-batch-processor:latest .

# Run via Docker Compose (full stack)
docker-compose up -d

# Run linting / static analysis
mvn checkstyle:check

# Generate coverage report
mvn verify
```

## Architecture

The application follows a Spring Batch job model, designed to be deployed as a Kubernetes Job or CronJob:

- **Job Configuration** (`src/main/java/.../job/`): Defines Spring Batch `Job` beans composed of `Step` beans. Each job represents a distinct batch operation (e.g., data ingestion, report generation, cleanup).
- **Step Processing** (`src/main/java/.../step/`): Each step contains an `ItemReader`, `ItemProcessor`, and `ItemWriter` following the standard chunk-oriented processing pattern.
- **Domain / Entities** (`src/main/java/.../domain/`): JPA entities and repositories for persistent state.
- **Kafka Integration** (`src/main/java/.../event/`): Producers publish job completion events; consumers can trigger jobs from external events.
- **Kubernetes Manifests** (`k8s/`): YAML manifests for Job, CronJob, ConfigMap, and Secret resources.

## REST API Standards

- All responses include a `timestamp` field
- `/health` endpoint via Spring Boot Actuator (with dependency checks)
- `/metrics` endpoint for Prometheus scraping
- Swagger UI available at `/swagger-ui.html`
- Static test page at `/static/index.html`

## Project Conventions

- Use Java Records for DTOs
- Use Lombok (`@Slf4j`, `@RequiredArgsConstructor`, etc.) to reduce boilerplate
- Path variables preferred over query params for resource identification
- Spring Batch `JobParameters` used for passing runtime arguments to jobs
- Job execution metadata persisted to the Spring Batch schema tables

## Kubernetes Deployment

Batch jobs are deployed as Kubernetes `Job` or `CronJob` resources. ConfigMaps hold non-sensitive configuration; Secrets hold credentials. The application reads config via Spring's `application.yml` with environment variable overrides for container-injected values.

## Author

- Name: Wallace Espindola
- Email: wallace.espindola@gmail.com
- GitHub: https://github.com/wallaceespindola/
- LinkedIn: https://www.linkedin.com/in/wallaceespindola/
