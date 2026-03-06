.PHONY: setup build test lint clean run stop run-win stop-win dev docker docker-down k8s-deploy k8s-delete logs

# ── Run / Stop — Linux / macOS ────────────────────────────────────────────────
run:
	@chmod +x run.sh && ./run.sh

stop:
	@chmod +x stop.sh && ./stop.sh

# ── Run / Stop — Windows (cmd / PowerShell) ───────────────────────────────────
run-win:
	run.bat

stop-win:
	stop.bat

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
	open http://localhost:8080/h2-console

health:
	curl -s http://localhost:8080/actuator/health | python3 -m json.tool
