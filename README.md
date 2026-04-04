# tinker-test-services

A multi-language test harness for [Tinker](https://github.com/your-org/tinker) — the AI-powered observability and incident response agent.

This project runs four microservices that emit structured JSON logs to Loki via Promtail and expose endpoints for triggering realistic multi-line stack traces. It is designed to test Tinker's log ingestion, anomaly detection, root-cause analysis, and GitHub integration across Python, Node.js, Java, and Go.

---

## Services

| Service | Language / Framework | Port | Description |
|---|---|---|---|
| `payments-api` | Python / FastAPI + structlog | 8001 | Payment processing, fraud checks, batch settlements |
| `auth-service` | Node.js / Express + winston | 8002 | Login, sessions, token validation |
| `order-service` | Java / Spring Boot + Logback JSON | 8003 | Order lifecycle, payment gateway integration |
| `inventory-service` | Go / Gin + zerolog | 8004 | Stock management, warehouse sync |

All services:
- Emit structured JSON logs to stdout (picked up by Promtail)
- Run a background loop emitting realistic business-context logs every 2-5 seconds
- Expose `POST /trigger-error?type=<type>` to produce real multi-line stack traces
- Expose `GET /health`

---

## Quick Start

### Prerequisites

- Docker and Docker Compose v2
- `curl` and `openssl` (for `generate_traffic.sh`)

### 1. Start everything

```bash
cd tinker-test-services
docker compose up --build
```

This starts:
- **Loki** at http://localhost:3100
- **Grafana** at http://localhost:3000 (anonymous auth, Loki pre-configured)
- **Promtail** (scrapes Docker container logs, ships to Loki)
- All 4 microservices

The first `docker compose up --build` will take a few minutes — Maven downloads Spring Boot dependencies and the Go build cache is cold.

### 2. Verify services are running

```bash
curl http://localhost:8001/health  # payments-api
curl http://localhost:8002/health  # auth-service
curl http://localhost:8003/health  # order-service
curl http://localhost:8004/health  # inventory-service
```

### 3. Open Grafana

Visit http://localhost:3000. Navigate to **Explore** and select the **Loki** datasource.

Example LogQL queries:

```logql
# All logs from all services
{service=~".+"}

# Only errors
{service=~".+"} | json | level="error"

# Payments service errors
{service="payments-api"} | json | level="error"

# Stack traces (multi-line)
{service=~".+"} | json | line_format "{{.traceback}}{{.stack_trace}}"

# Auth service — suspicious logins
{service="auth-service"} | json | message="suspicious login detected"
```

---

## Triggering Incidents

### Using generate_traffic.sh

```bash
# Continuous normal traffic to all services
./generate_traffic.sh

# Trigger all error types on all services (produces stack traces in Loki)
./generate_traffic.sh --incident

# Target a single service
./generate_traffic.sh --incident --service payments
./generate_traffic.sh --incident --service auth
./generate_traffic.sh --incident --service orders
./generate_traffic.sh --incident --service inventory

# Normal traffic to a single service
./generate_traffic.sh --service inventory
```

### Manual curl

```bash
# payments-api
curl -X POST "http://localhost:8001/trigger-error?type=null_pointer"
curl -X POST "http://localhost:8001/trigger-error?type=db_timeout"
curl -X POST "http://localhost:8001/trigger-error?type=divide_by_zero"

# auth-service
curl -X POST "http://localhost:8002/trigger-error?type=null_pointer"
curl -X POST "http://localhost:8002/trigger-error?type=db_timeout"
curl -X POST "http://localhost:8002/trigger-error?type=unhandled_promise"

# order-service
curl -X POST "http://localhost:8003/trigger-error?type=null_pointer"
curl -X POST "http://localhost:8003/trigger-error?type=db_timeout"
curl -X POST "http://localhost:8003/trigger-error?type=stack_overflow"

# inventory-service
curl -X POST "http://localhost:8004/trigger-error?type=null_pointer"
curl -X POST "http://localhost:8004/trigger-error?type=index_out_of_bounds"
curl -X POST "http://localhost:8004/trigger-error?type=db_timeout"
```

---

## Business Endpoints

### payments-api (port 8001)

```bash
# Process a payment
curl -X POST http://localhost:8001/pay \
  -H "Content-Type: application/json" \
  -d '{"user_id":"usr_0001","amount":99.99,"currency":"USD"}'

# Look up a transaction
curl http://localhost:8001/transactions/txn_abc123
```

### auth-service (port 8002)

```bash
# Login
curl -X POST http://localhost:8002/login \
  -H "Content-Type: application/json" \
  -d '{"user_id":"usr_0001","method":"password"}'

# Validate token (use session_id from login response)
curl http://localhost:8002/validate \
  -H "Authorization: Bearer <session_id>"

# Logout
curl -X POST http://localhost:8002/logout \
  -H "Content-Type: application/json" \
  -d '{"session_id":"<session_id>"}'
```

### order-service (port 8003)

```bash
# Create an order
curl -X POST http://localhost:8003/orders \
  -H "Content-Type: application/json" \
  -d '{"user_id":"usr_0001","items":["SKU-ALPHA","SKU-BETA"],"total":149.99}'

# Get an order
curl http://localhost:8003/orders/<order_id>
```

### inventory-service (port 8004)

```bash
# List all items
curl http://localhost:8004/items

# Get a specific item
curl http://localhost:8004/items/item_0001

# Reserve stock
curl -X POST http://localhost:8004/reserve \
  -H "Content-Type: application/json" \
  -d '{"item_id":"item_0001","quantity":2,"order_id":"ord_abc123"}'
```

---

## Connecting Tinker

### Option 1 — Local Tinker with Grafana backend

Point your Tinker server's `TINKER_BACKEND=grafana` and configure it to talk to the Loki instance:

```bash
# In your Tinker .env
TINKER_BACKEND=grafana
GRAFANA_URL=http://localhost:3000
LOKI_URL=http://localhost:3100
```

Then analyze one of the test services:

```bash
tinker analyze payments-api --since 30m
```

### Option 2 — Remote MCP via Claude Code

If you are running the full Tinker server, add it to your `.claude/settings.json`:

```json
{
  "mcpServers": {
    "tinker": {
      "transport": "sse",
      "url": "http://localhost:8080/mcp/sse",
      "headers": { "Authorization": "Bearer ${TINKER_API_TOKEN}" }
    }
  }
}
```

Then ask Claude Code: *"Analyze the payments-api service for errors in the last hour."*

---

## Log Formats

Each service emits different JSON shapes — useful for testing Tinker's log normalization.

### Python / structlog (payments-api)
```json
{"timestamp":"2026-04-04T10:00:00.000Z","level":"error","service":"payments-api","message":"payment failed","user_id":"usr_0001","transaction_id":"txn_abc123","amount":99.99,"currency":"USD","reason":"insufficient_funds"}
```

### Node.js / winston (auth-service)
```json
{"timestamp":"2026-04-04T10:00:00.000Z","level":"warn","service":"auth-service","message":"suspicious login detected","user_id":"usr_0001","ip":"198.51.100.99","risk_score":"0.872"}
```

### Java / logstash-logback-encoder (order-service)
```json
{"@timestamp":"2026-04-04T10:00:00.000Z","level":"ERROR","logger_name":"com.tinker.orders.OrderController","message":"NullPointerException in order processing","service":"order-service","order_id":"ord_null_test","stack_trace":"java.lang.NullPointerException\n\tat com.tinker.orders.OrderService.triggerNullPointer..."}
```

### Go / zerolog (inventory-service)
```json
{"time":"2026-04-04T10:00:00.000000000Z","level":"error","service":"inventory-service","message":"panic: nil pointer dereference in inventory lookup","error_type":"nil_pointer_dereference","stack_trace":"goroutine 1 [running]:\nruntime/debug.Stack()\n\t..."}
```

---

## Infrastructure Deployment

### AWS ECS Fargate

```bash
cd infra/aws
terraform init
terraform apply \
  -var="aws_region=us-east-1" \
  -var="environment=dev" \
  -var="ecr_registry=123456789012.dkr.ecr.us-east-1.amazonaws.com" \
  -var="image_tag=latest"
```

Build and push images to ECR first:

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

for svc in payments-api auth-service order-service inventory-service; do
  docker build -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/${svc}:latest services/${svc}/
  docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/${svc}:latest
done
```

### GCP Cloud Run

```bash
cd infra/gcp
terraform init
terraform apply \
  -var="project_id=my-gcp-project" \
  -var="region=us-central1" \
  -var="environment=dev" \
  -var="artifact_registry=us-central1-docker.pkg.dev/my-gcp-project/tinker" \
  -var="image_tag=latest"
```

### Azure Container Apps

```bash
cd infra/azure
terraform init
terraform apply \
  -var="resource_group=tinker-test-rg" \
  -var="location=eastus" \
  -var="environment=dev" \
  -var="acr_login_server=myregistry.azurecr.io" \
  -var="image_tag=latest"
```

---

## Stopping

```bash
docker compose down          # stop containers, keep volumes
docker compose down -v       # stop containers and delete Loki/Grafana data
```
