#!/usr/bin/env bash
# generate_traffic.sh — Send synthetic traffic to all tinker-test-services
#
# Usage:
#   ./generate_traffic.sh                     # random traffic to all services
#   ./generate_traffic.sh --incident          # trigger errors on all services
#   ./generate_traffic.sh --service payments  # target one service only
#   ./generate_traffic.sh --incident --service auth
#   ./generate_traffic.sh --help

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
PAYMENTS_URL="${PAYMENTS_URL:-http://localhost:8001}"
AUTH_URL="${AUTH_URL:-http://localhost:8002}"
ORDERS_URL="${ORDERS_URL:-http://localhost:8003}"
INVENTORY_URL="${INVENTORY_URL:-http://localhost:8004}"

INCIDENT_MODE=false
TARGET_SERVICE="all"
LOOP_INTERVAL=1   # seconds between requests in normal mode

USERS=(usr_0001 usr_0002 usr_0003 usr_0004 usr_0005 usr_0010 usr_0020)
CURRENCIES=(USD EUR GBP CAD AUD)
ITEMS=(item_0001 item_0002 item_0003 item_0004 item_0005)
ORDER_ITEMS=(SKU-ALPHA SKU-BETA SKU-GAMMA SKU-DELTA SKU-EPSILON)

# ANSI colours
RED='\033[0;31m'
YLW='\033[1;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
RST='\033[0m'

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --incident               Trigger error endpoints on all targeted services
  --service <name>         Target a single service: payments, auth, orders, inventory
  --loop-interval <secs>   Seconds between request bursts in normal mode (default: 1)
  --help                   Show this help message

Environment variables:
  PAYMENTS_URL   Base URL for payments-api  (default: http://localhost:8001)
  AUTH_URL       Base URL for auth-service  (default: http://localhost:8002)
  ORDERS_URL     Base URL for order-service (default: http://localhost:8003)
  INVENTORY_URL  Base URL for inventory-service (default: http://localhost:8004)

Examples:
  # Steady random traffic to all services
  ./generate_traffic.sh

  # Trigger all error types on all services (simulates an incident)
  ./generate_traffic.sh --incident

  # Only hammer the payments service
  ./generate_traffic.sh --service payments

  # Trigger incident on auth service only
  ./generate_traffic.sh --incident --service auth
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --incident)       INCIDENT_MODE=true; shift ;;
    --service)        TARGET_SERVICE="$2"; shift 2 ;;
    --loop-interval)  LOOP_INTERVAL="$2"; shift 2 ;;
    --help|-h)        usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
rand_element() {
  local arr=("$@")
  echo "${arr[$((RANDOM % ${#arr[@]}))]}"
}

rand_amount() {
  # Random float between 1.00 and 999.99
  echo "$(( (RANDOM % 99899 + 100) )).$(( RANDOM % 100 ))" | awk '{printf "%.2f", $1/100}'
}

rand_quantity() {
  echo $(( RANDOM % 5 + 1 ))
}

http_post() {
  local url="$1"
  local body="$2"
  curl -sf -X POST "$url" \
       -H "Content-Type: application/json" \
       -d "$body" \
       -o /dev/null \
       -w "%{http_code}" \
       --max-time 10 \
  || echo "000"
}

http_get() {
  local url="$1"
  curl -sf "$url" \
       -o /dev/null \
       -w "%{http_code}" \
       --max-time 10 \
  || echo "000"
}

log_req() {
  local svc="$1" method="$2" path="$3" status="$4"
  local colour="$GRN"
  [[ "$status" =~ ^5 ]] && colour="$RED"
  [[ "$status" =~ ^4 ]] && colour="$YLW"
  [[ "$status" == "000" ]] && colour="$RED"
  printf "${CYN}[%s]${RST} %-20s %-6s %-40s → ${colour}%s${RST}\n" \
    "$(date '+%H:%M:%S')" "$svc" "$method" "$path" "$status"
}

# ---------------------------------------------------------------------------
# Health checks
# ---------------------------------------------------------------------------
check_service() {
  local name="$1" url="$2"
  local status
  status=$(http_get "${url}/health")
  if [[ "$status" == "200" ]]; then
    printf "${GRN}[OK]${RST}  %s at %s\n" "$name" "$url"
    return 0
  else
    printf "${RED}[DOWN]${RST} %s at %s (HTTP %s)\n" "$name" "$url" "$status"
    return 1
  fi
}

check_all_services() {
  echo ""
  echo "Checking service health..."
  local all_ok=true
  check_service "payments-api"      "$PAYMENTS_URL"  || all_ok=false
  check_service "auth-service"      "$AUTH_URL"      || all_ok=false
  check_service "order-service"     "$ORDERS_URL"    || all_ok=false
  check_service "inventory-service" "$INVENTORY_URL" || all_ok=false
  echo ""
  if [[ "$all_ok" == "false" ]]; then
    echo -e "${YLW}Warning: one or more services are not healthy. Continuing anyway...${RST}"
  fi
}

# ---------------------------------------------------------------------------
# Normal traffic functions
# ---------------------------------------------------------------------------
traffic_payments() {
  local user
  user=$(rand_element "${USERS[@]}")
  local amount
  amount=$(rand_amount)
  local currency
  currency=$(rand_element "${CURRENCIES[@]}")

  # POST /pay
  local status
  status=$(http_post "${PAYMENTS_URL}/pay" \
    "{\"user_id\":\"${user}\",\"amount\":${amount},\"currency\":\"${currency}\"}")
  log_req "payments-api" "POST" "/pay" "$status"

  # GET /transactions/<id> — use a fake ID sometimes to produce 404
  local txn_id="txn_$(openssl rand -hex 6 2>/dev/null || echo 'aabbccdd1234')"
  status=$(http_get "${PAYMENTS_URL}/transactions/${txn_id}")
  log_req "payments-api" "GET" "/transactions/${txn_id}" "$status"
}

traffic_auth() {
  local user
  user=$(rand_element "${USERS[@]}")

  # POST /login
  local status session_id
  local login_resp
  login_resp=$(curl -sf -X POST "${AUTH_URL}/login" \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":\"${user}\",\"method\":\"password\"}" \
    --max-time 10 2>/dev/null || echo '{}')
  status=$(echo "$login_resp" | grep -o '"session_id"' | head -1 | wc -l | tr -d ' ')
  [[ "$status" -gt 0 ]] && status="200" || status="500"
  log_req "auth-service" "POST" "/login" "$status"

  # GET /validate — with the session_id we got
  session_id=$(echo "$login_resp" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 || echo "")
  if [[ -n "$session_id" ]]; then
    local vstatus
    vstatus=$(curl -sf "${AUTH_URL}/validate" \
      -H "Authorization: Bearer ${session_id}" \
      -o /dev/null -w "%{http_code}" --max-time 5 2>/dev/null || echo "000")
    log_req "auth-service" "GET" "/validate" "$vstatus"
  fi
}

traffic_orders() {
  local user
  user=$(rand_element "${USERS[@]}")
  local item1 item2
  item1=$(rand_element "${ORDER_ITEMS[@]}")
  item2=$(rand_element "${ORDER_ITEMS[@]}")
  local total
  total=$(rand_amount)

  # POST /orders
  local status
  status=$(http_post "${ORDERS_URL}/orders" \
    "{\"user_id\":\"${user}\",\"items\":[\"${item1}\",\"${item2}\"],\"total\":${total}}")
  log_req "order-service" "POST" "/orders" "$status"

  # GET /orders/<fake_id>
  local ord_id="ord_$(openssl rand -hex 6 2>/dev/null || echo 'aabbccdd1234')"
  status=$(http_get "${ORDERS_URL}/orders/${ord_id}")
  log_req "order-service" "GET" "/orders/${ord_id}" "$status"
}

traffic_inventory() {
  # GET /items
  local status
  status=$(http_get "${INVENTORY_URL}/items")
  log_req "inventory-service" "GET" "/items" "$status"

  # GET /items/:id
  local item_id
  item_id=$(rand_element "${ITEMS[@]}")
  status=$(http_get "${INVENTORY_URL}/items/${item_id}")
  log_req "inventory-service" "GET" "/items/${item_id}" "$status"

  # POST /reserve
  local order_id="ord_$(openssl rand -hex 6 2>/dev/null || echo 'aabbccdd1234')"
  status=$(http_post "${INVENTORY_URL}/reserve" \
    "{\"item_id\":\"${item_id}\",\"quantity\":1,\"order_id\":\"${order_id}\"}")
  log_req "inventory-service" "POST" "/reserve" "$status"
}

# ---------------------------------------------------------------------------
# Incident traffic functions
# ---------------------------------------------------------------------------
trigger_errors_payments() {
  for error_type in null_pointer db_timeout divide_by_zero; do
    local status
    status=$(curl -sf -X POST "${PAYMENTS_URL}/trigger-error?type=${error_type}" \
      -o /dev/null -w "%{http_code}" --max-time 15 2>/dev/null || echo "000")
    log_req "payments-api" "POST" "/trigger-error?type=${error_type}" "$status"
    sleep 0.5
  done
}

trigger_errors_auth() {
  for error_type in null_pointer db_timeout unhandled_promise; do
    local status
    status=$(curl -sf -X POST "${AUTH_URL}/trigger-error?type=${error_type}" \
      -o /dev/null -w "%{http_code}" --max-time 15 2>/dev/null || echo "000")
    log_req "auth-service" "POST" "/trigger-error?type=${error_type}" "$status"
    sleep 0.5
  done
}

trigger_errors_orders() {
  for error_type in null_pointer db_timeout stack_overflow; do
    local status
    status=$(curl -sf -X POST "${ORDERS_URL}/trigger-error?type=${error_type}" \
      -o /dev/null -w "%{http_code}" --max-time 15 2>/dev/null || echo "000")
    log_req "order-service" "POST" "/trigger-error?type=${error_type}" "$status"
    sleep 0.5
  done
}

trigger_errors_inventory() {
  for error_type in null_pointer index_out_of_bounds db_timeout; do
    local status
    status=$(curl -sf -X POST "${INVENTORY_URL}/trigger-error?type=${error_type}" \
      -o /dev/null -w "%{http_code}" --max-time 15 2>/dev/null || echo "000")
    log_req "inventory-service" "POST" "/trigger-error?type=${error_type}" "$status"
    sleep 0.5
  done
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
check_all_services

if [[ "$INCIDENT_MODE" == "true" ]]; then
  echo -e "${RED}INCIDENT MODE${RST} — triggering errors on ${TARGET_SERVICE} services"
  echo ""
  case "$TARGET_SERVICE" in
    all)
      trigger_errors_payments
      trigger_errors_auth
      trigger_errors_orders
      trigger_errors_inventory
      ;;
    payments)  trigger_errors_payments  ;;
    auth)      trigger_errors_auth      ;;
    orders)    trigger_errors_orders    ;;
    inventory) trigger_errors_inventory ;;
    *)
      echo "Unknown service: ${TARGET_SERVICE}. Valid: all, payments, auth, orders, inventory"
      exit 1
      ;;
  esac
  echo ""
  echo -e "${GRN}Done. Check your Loki/Grafana dashboard for stack traces.${RST}"
  exit 0
fi

# Normal traffic loop
echo -e "${GRN}Normal traffic mode${RST} — sending to ${TARGET_SERVICE} (Ctrl-C to stop)"
echo ""

while true; do
  case "$TARGET_SERVICE" in
    all)
      traffic_payments
      traffic_auth
      traffic_orders
      traffic_inventory
      ;;
    payments)  traffic_payments  ;;
    auth)      traffic_auth      ;;
    orders)    traffic_orders    ;;
    inventory) traffic_inventory ;;
    *)
      echo "Unknown service: ${TARGET_SERVICE}. Valid: all, payments, auth, orders, inventory"
      exit 1
      ;;
  esac
  sleep "$LOOP_INTERVAL"
done
