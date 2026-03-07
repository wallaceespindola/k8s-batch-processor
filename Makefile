.PHONY: setup build test lint clean run stop run-win stop-win run-ps stop-ps run-docker stop-docker run-docker-win stop-docker-win run-docker-ps stop-docker-ps dev docker docker-down k8s-deploy k8s-delete logs

# ── Run / Stop — Linux / macOS ────────────────────────────────────────────────
run:
	@chmod +x run.sh && ./run.sh

stop:
	@chmod +x stop.sh && ./stop.sh

# ── Run / Stop — Windows cmd ──────────────────────────────────────────────────
run-win:
	run.bat

stop-win:
	stop.bat

# ── Run / Stop — Windows PowerShell ───────────────────────────────────────────
run-ps:
	powershell -ExecutionPolicy Bypass -File run.ps1

stop-ps:
	powershell -ExecutionPolicy Bypass -File stop.ps1

# ── Run / Stop — Kubernetes via Docker (minikube) — Linux / macOS ─────────────
# Usage: make run-docker          (default 4 pods)
#        make run-docker PODS=2   (custom pod count)
run-docker:
	@chmod +x run-docker.sh && ./run-docker.sh $(PODS)

stop-docker:
	@chmod +x stop-docker.sh && ./stop-docker.sh

# ── Run / Stop — Kubernetes via Docker (minikube) — Windows cmd ───────────────
run-docker-win:
	run-docker.bat $(PODS)

stop-docker-win:
	stop-docker.bat

# ── Run / Stop — Kubernetes via Docker (minikube) — Windows PowerShell ────────
run-docker-ps:
	powershell -ExecutionPolicy Bypass -File run-docker.ps1 -Pods $(if $(PODS),$(PODS),4)

stop-docker-ps:
	powershell -ExecutionPolicy Bypass -File stop-docker.ps1

# ── Development ───────────────────────────────────────────────────────────────
setup:
	mvn dependency:resolve

dev:
	mvn spring-boot:run

build:
	mvn clean package -DskipTests

test:
	mvn test

test-single:
	mvn test -Dtest=$(CLASS)

test-coverage:
	mvn verify

lint:
	mvn checkstyle:check

clean:
	mvn clean

# ── Docker ────────────────────────────────────────────────────────────────────
docker:
	docker-compose up --build -d

docker-down:
	docker-compose down

docker-logs:
	docker-compose logs -f

docker-image:
	mvn spring-boot:build-image

# ── Kubernetes ────────────────────────────────────────────────────────────────
k8s-deploy:
	kubectl apply -f k8s/

k8s-delete:
	kubectl delete -f k8s/

k8s-status:
	kubectl get pods -l app=k8s-batch-processor

k8s-logs:
	kubectl logs -l app=k8s-batch-processor --tail=100 -f

# ── Utilities ─────────────────────────────────────────────────────────────────
open:
	open http://localhost:8080

swagger:
	open http://localhost:8080/swagger-ui.html

h2:
	open http://localhost:8080/h2.html

health:
	curl -s http://localhost:8080/actuator/health | python3 -m json.tool
