import asyncio
import random
import traceback
import uuid
from datetime import datetime, timezone
from typing import Optional

import structlog
import uvicorn
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel

# Configure structlog for JSON output
structlog.configure(
    processors=[
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.BoundLogger,
    context_class=dict,
    logger_factory=structlog.PrintLoggerFactory(),
)

log = structlog.get_logger().bind(service="payments-api")

app = FastAPI(title="Payments API", version="1.0.0")

# ---------------------------------------------------------------------------
# In-memory store for demo transactions
# ---------------------------------------------------------------------------
TRANSACTIONS: dict[str, dict] = {}

USERS = [f"usr_{i:04d}" for i in range(1, 50)]
CURRENCIES = ["USD", "EUR", "GBP", "CAD", "AUD"]
MERCHANTS = ["stripe", "paypal", "braintree", "adyen", "square"]


# ---------------------------------------------------------------------------
# Background log loop
# ---------------------------------------------------------------------------
async def background_log_loop() -> None:
    """Emit realistic payment-domain logs every 2-5 seconds."""
    scenarios = [
        _log_payment_processed,
        _log_slow_db_query,
        _log_rate_limit_approaching,
        _log_payment_failed,
        _log_fraud_check_passed,
        _log_fraud_check_failed,
        _log_payment_retried,
        _log_batch_settlement,
    ]
    while True:
        await asyncio.sleep(random.uniform(2, 5))
        try:
            await random.choice(scenarios)()
        except Exception:
            pass


async def _log_payment_processed() -> None:
    txn_id = f"txn_{uuid.uuid4().hex[:12]}"
    user_id = random.choice(USERS)
    amount = round(random.uniform(1.0, 9999.99), 2)
    currency = random.choice(CURRENCIES)
    log.info(
        "payment processed",
        user_id=user_id,
        transaction_id=txn_id,
        amount=amount,
        currency=currency,
        merchant=random.choice(MERCHANTS),
        latency_ms=random.randint(45, 320),
    )


async def _log_slow_db_query() -> None:
    latency = random.randint(800, 4500)
    log.warning(
        "slow DB query detected",
        query="SELECT * FROM transactions WHERE user_id = $1 AND status = $2",
        latency_ms=latency,
        threshold_ms=500,
        table="transactions",
    )


async def _log_rate_limit_approaching() -> None:
    current = random.randint(850, 980)
    log.warning(
        "rate limit approaching",
        user_id=random.choice(USERS),
        requests_this_minute=current,
        limit=1000,
        pct_used=current / 10,
    )


async def _log_payment_failed() -> None:
    log.error(
        "payment failed",
        user_id=random.choice(USERS),
        transaction_id=f"txn_{uuid.uuid4().hex[:12]}",
        amount=round(random.uniform(10.0, 500.0), 2),
        currency=random.choice(CURRENCIES),
        reason=random.choice(
            ["insufficient_funds", "card_declined", "expired_card", "invalid_cvv"]
        ),
        gateway_code=random.choice(["4001", "4002", "4003", "4005"]),
    )


async def _log_fraud_check_passed() -> None:
    log.info(
        "fraud check passed",
        user_id=random.choice(USERS),
        transaction_id=f"txn_{uuid.uuid4().hex[:12]}",
        risk_score=round(random.uniform(0.0, 0.35), 3),
        model_version="fraud-v2.4.1",
        latency_ms=random.randint(12, 80),
    )


async def _log_fraud_check_failed() -> None:
    log.error(
        "fraud check failed — transaction blocked",
        user_id=random.choice(USERS),
        transaction_id=f"txn_{uuid.uuid4().hex[:12]}",
        risk_score=round(random.uniform(0.75, 0.99), 3),
        model_version="fraud-v2.4.1",
        signals=["velocity_spike", "new_device", "unusual_geo"],
    )


async def _log_payment_retried() -> None:
    attempt = random.randint(2, 4)
    log.warning(
        "payment retry attempt",
        transaction_id=f"txn_{uuid.uuid4().hex[:12]}",
        attempt=attempt,
        max_attempts=4,
        backoff_ms=attempt * 500,
    )


async def _log_batch_settlement() -> None:
    count = random.randint(50, 500)
    log.info(
        "batch settlement completed",
        batch_id=f"batch_{uuid.uuid4().hex[:8]}",
        transactions_count=count,
        total_amount=round(count * random.uniform(30.0, 200.0), 2),
        currency="USD",
        duration_ms=random.randint(200, 2000),
    )


# ---------------------------------------------------------------------------
# Startup / shutdown
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup_event() -> None:
    log.info("payments-api starting up", port=8001)
    asyncio.create_task(background_log_loop())


# ---------------------------------------------------------------------------
# Health endpoint
# ---------------------------------------------------------------------------
@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "payments-api", "timestamp": datetime.now(timezone.utc).isoformat()}


# ---------------------------------------------------------------------------
# Business endpoints
# ---------------------------------------------------------------------------
class PayRequest(BaseModel):
    user_id: str
    amount: float
    currency: str = "USD"
    merchant: Optional[str] = None


@app.post("/pay")
async def pay(req: PayRequest) -> dict:
    txn_id = f"txn_{uuid.uuid4().hex[:12]}"
    log.info(
        "initiating payment",
        user_id=req.user_id,
        transaction_id=txn_id,
        amount=req.amount,
        currency=req.currency,
    )
    TRANSACTIONS[txn_id] = {
        "id": txn_id,
        "user_id": req.user_id,
        "amount": req.amount,
        "currency": req.currency,
        "status": "completed",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    log.info(
        "payment completed",
        user_id=req.user_id,
        transaction_id=txn_id,
        amount=req.amount,
        currency=req.currency,
    )
    return TRANSACTIONS[txn_id]


@app.get("/transactions/{txn_id}")
async def get_transaction(txn_id: str) -> dict:
    log.debug("transaction lookup", transaction_id=txn_id)
    if txn_id not in TRANSACTIONS:
        log.warning("transaction not found", transaction_id=txn_id)
        raise HTTPException(status_code=404, detail="Transaction not found")
    return TRANSACTIONS[txn_id]


# ---------------------------------------------------------------------------
# Trigger-error endpoint
# ---------------------------------------------------------------------------
@app.post("/trigger-error")
async def trigger_error(type: str = Query(..., description="Error type to trigger")) -> dict:
    log.warning("trigger-error endpoint called", error_type=type)

    if type == "null_pointer":
        return _raise_null_pointer()
    elif type == "db_timeout":
        return _raise_db_timeout()
    elif type == "divide_by_zero":
        return _raise_divide_by_zero()
    else:
        raise HTTPException(status_code=400, detail=f"Unknown error type: {type}. Valid types: null_pointer, db_timeout, divide_by_zero")


def _raise_null_pointer() -> dict:
    """Simulate AttributeError on None — produces realistic traceback."""
    try:
        payment_processor = None  # simulates a failed DB lookup
        # This will raise AttributeError
        charge_result = payment_processor.charge(amount=99.99, currency="USD")  # type: ignore[union-attr]
        return {"result": charge_result}
    except AttributeError as exc:
        tb_str = traceback.format_exc()
        log.error(
            "null pointer error in payment processor",
            error=str(exc),
            error_type="AttributeError",
            traceback=tb_str,
            user_id=random.choice(USERS),
            transaction_id=f"txn_{uuid.uuid4().hex[:12]}",
        )
        raise HTTPException(status_code=500, detail=f"AttributeError: {exc}")


def _db_query_inner(depth: int, user_id: str) -> list:
    """Recursively calls itself to produce a deeper stack trace."""
    if depth == 0:
        conn = None  # simulates a timed-out connection
        return conn.execute("SELECT * FROM transactions WHERE user_id = %s", (user_id,))  # type: ignore[union-attr]
    return _db_query_inner(depth - 1, user_id)


def _raise_db_timeout() -> dict:
    """Simulate database connection pool exhaustion."""
    try:
        user_id = random.choice(USERS)
        log.warning(
            "database connection pool exhausted — retrying",
            pool_size=10,
            active_connections=10,
            waiting_requests=24,
            user_id=user_id,
        )
        _db_query_inner(3, user_id)
        return {}
    except (AttributeError, TimeoutError) as exc:
        tb_str = traceback.format_exc()
        log.error(
            "database timeout — connection pool exhausted",
            error=str(exc),
            error_type=type(exc).__name__,
            traceback=tb_str,
            pool_host="postgres-primary.payments.internal",
            pool_port=5432,
            timeout_ms=5000,
        )
        raise HTTPException(status_code=503, detail=f"TimeoutError: Database connection pool exhausted after 5000ms")


def _calculate_fee(amount: float, zero_divisor: int) -> float:
    """Calculates a fee — will divide by zero if divisor is 0."""
    base_fee = amount / zero_divisor
    return round(base_fee * 0.029, 4)


def _raise_divide_by_zero() -> dict:
    """Simulate ZeroDivisionError in fee calculation."""
    try:
        amount = round(random.uniform(10.0, 1000.0), 2)
        log.info("calculating transaction fee", amount=amount, fee_model="percentage")
        fee = _calculate_fee(amount, 0)
        return {"fee": fee}
    except ZeroDivisionError as exc:
        tb_str = traceback.format_exc()
        log.error(
            "zero division error in fee calculation",
            error=str(exc),
            error_type="ZeroDivisionError",
            traceback=tb_str,
            fee_model="percentage",
            divisor=0,
        )
        raise HTTPException(status_code=500, detail=f"ZeroDivisionError: {exc}")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
