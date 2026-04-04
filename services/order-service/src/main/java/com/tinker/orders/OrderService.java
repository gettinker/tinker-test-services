package com.tinker.orders;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.ThreadContext;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class OrderService {

    private static final Logger log = LogManager.getLogger(OrderService.class);
    private static final Random RNG = new Random();

    private static final List<String> USERS =
            List.of("usr_0001","usr_0002","usr_0003","usr_0004","usr_0005",
                    "usr_0010","usr_0020","usr_0030","usr_0040","usr_0050");

    private static final List<String> ITEMS =
            List.of("SKU-ALPHA","SKU-BETA","SKU-GAMMA","SKU-DELTA","SKU-EPSILON");

    private static final List<String> PAYMENT_GATEWAYS =
            List.of("stripe","paypal","adyen","braintree");

    // In-memory store
    final Map<String, Order> orders = new ConcurrentHashMap<>();

    // -------------------------------------------------------------------------
    // Background log loop — every 3 seconds
    // -------------------------------------------------------------------------
    @Scheduled(fixedDelay = 3000)
    public void backgroundLogLoop() {
        int scenario = RNG.nextInt(8);
        try {
            switch (scenario) {
                case 0 -> logOrderCreated();
                case 1 -> logOrderProcessing();
                case 2 -> logPaymentGatewayTimeout();
                case 3 -> logInventoryCheck();
                case 4 -> logOrderShipped();
                case 5 -> logOrderFailed();
                case 6 -> logBatchProcessing();
                default -> logMetricsSummary();
            }
        } catch (Exception e) {
            ThreadContext.put("error_type", e.getClass().getSimpleName());
            log.error("background loop error", e);
        } finally {
            ThreadContext.clearAll();
        }
    }

    private void logOrderCreated() {
        String orderId = "ord_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
        String userId  = randomUser();
        double total   = Math.round(RNG.nextDouble() * 500 + 10);
        ThreadContext.put("order_id", orderId);
        ThreadContext.put("user_id", userId);
        ThreadContext.put("item_count", String.valueOf(RNG.nextInt(5) + 1));
        ThreadContext.put("total", String.valueOf(total));
        ThreadContext.put("currency", "USD");
        ThreadContext.put("payment_gateway", randomGateway());
        log.info("Order created");
    }

    private void logOrderProcessing() {
        ThreadContext.put("batch_size", String.valueOf(RNG.nextInt(20) + 1));
        ThreadContext.put("queue_depth", String.valueOf(RNG.nextInt(100)));
        ThreadContext.put("worker_id", "worker-" + RNG.nextInt(4));
        ThreadContext.put("processing_ms", String.valueOf(RNG.nextInt(400) + 50));
        log.info("Processing order batch");
    }

    private void logPaymentGatewayTimeout() {
        ThreadContext.put("gateway", randomGateway());
        ThreadContext.put("order_id", "ord_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));
        ThreadContext.put("timeout_ms", "5000");
        ThreadContext.put("attempt", String.valueOf(RNG.nextInt(3) + 1));
        ThreadContext.put("will_retry", "true");
        log.warn("Payment gateway timeout");
    }

    private void logInventoryCheck() {
        String sku = randomItem();
        int qty = RNG.nextInt(500);
        ThreadContext.put("sku", sku);
        ThreadContext.put("quantity", String.valueOf(qty));
        ThreadContext.put("reorder_threshold", "10");
        ThreadContext.put("warehouse", "us-east-1");
        if (qty < 10) {
            log.warn("Low inventory detected");
        } else {
            log.debug("Inventory check passed");
        }
    }

    private void logOrderShipped() {
        ThreadContext.put("order_id", "ord_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));
        ThreadContext.put("user_id", randomUser());
        ThreadContext.put("carrier", "UPS");
        ThreadContext.put("tracking_number", "1Z" + UUID.randomUUID().toString().replace("-", "").substring(0, 16).toUpperCase());
        ThreadContext.put("estimated_delivery", Instant.now().plusSeconds(86400 * 3).toString());
        log.info("Order shipped");
    }

    private void logOrderFailed() {
        String[] reasons = {"payment_declined", "inventory_unavailable", "fraud_block"};
        ThreadContext.put("order_id", "ord_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));
        ThreadContext.put("user_id", randomUser());
        ThreadContext.put("reason", reasons[RNG.nextInt(reasons.length)]);
        ThreadContext.put("will_notify_customer", "true");
        log.error("Order processing failed");
    }

    private void logBatchProcessing() {
        int count = RNG.nextInt(50) + 10;
        int failures = RNG.nextInt(3);
        ThreadContext.put("orders_processed", String.valueOf(count));
        ThreadContext.put("success_count", String.valueOf(count - failures));
        ThreadContext.put("failure_count", String.valueOf(failures));
        ThreadContext.put("duration_ms", String.valueOf(RNG.nextInt(2000) + 100));
        log.info("Batch order processing complete");
    }

    private void logMetricsSummary() {
        ThreadContext.put("total_orders_today", String.valueOf(RNG.nextInt(10000) + 500));
        ThreadContext.put("avg_order_value", String.valueOf(Math.round(RNG.nextDouble() * 200 + 20)));
        ThreadContext.put("conversion_rate", String.format("%.2f", RNG.nextDouble() * 5 + 2));
        log.info("Order metrics summary");
    }

    // -------------------------------------------------------------------------
    // Business logic
    // -------------------------------------------------------------------------
    public Order createOrder(String userId, List<String> items, double total) {
        String orderId = "ord_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
        Order order = new Order(orderId, userId, items, total, "pending", Instant.now().toString());
        orders.put(orderId, order);
        ThreadContext.put("order_id", orderId);
        ThreadContext.put("user_id", userId);
        ThreadContext.put("item_count", String.valueOf(items.size()));
        ThreadContext.put("total", String.valueOf(total));
        log.info("Order created via API");
        ThreadContext.clearAll();
        return order;
    }

    public Order getOrder(String orderId) {
        Order order = orders.get(orderId);
        ThreadContext.put("order_id", orderId);
        if (order == null) {
            log.warn("Order not found");
        } else {
            log.debug("Order retrieved");
        }
        ThreadContext.clearAll();
        return order;
    }

    // -------------------------------------------------------------------------
    // Error triggers
    // -------------------------------------------------------------------------
    public void triggerNullPointer() {
        Order order = null;
        // NullPointerException — real Java stack trace
        String status = order.getStatus();
        log.info("Order status: {}", status);
    }

    public void triggerDbTimeout() {
        simulateDbCall(5);
    }

    private void simulateDbCall(int depth) {
        if (depth == 0) {
            throw new org.springframework.dao.DataAccessResourceFailureException(
                    "Unable to acquire JDBC Connection — " +
                    "com.zaxxer.hikari.pool.HikariPool$PoolInitializationException: " +
                    "Failed to initialize pool: Connection to postgres-orders.internal:5432 refused. " +
                    "Connection timeout after 30000ms");
        }
        simulateDbCall(depth - 1);
    }

    public void triggerStackOverflow() {
        triggerStackOverflow(); // infinite recursion → StackOverflowError
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    private String randomUser()    { return USERS.get(RNG.nextInt(USERS.size())); }
    private String randomItem()    { return ITEMS.get(RNG.nextInt(ITEMS.size())); }
    private String randomGateway() { return PAYMENT_GATEWAYS.get(RNG.nextInt(PAYMENT_GATEWAYS.size())); }
}
