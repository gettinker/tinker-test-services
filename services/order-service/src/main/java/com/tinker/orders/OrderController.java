package com.tinker.orders;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.ThreadContext;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
public class OrderController {

    private static final Logger log = LogManager.getLogger(OrderController.class);
    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    // -------------------------------------------------------------------------
    // Health
    // -------------------------------------------------------------------------
    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of("status", "ok", "service", "order-service"));
    }

    // -------------------------------------------------------------------------
    // Business endpoints
    // -------------------------------------------------------------------------
    @PostMapping("/orders")
    public ResponseEntity<?> createOrder(@RequestBody Map<String, Object> body) {
        String userId = (String) body.getOrDefault("user_id", "usr_0001");
        @SuppressWarnings("unchecked")
        List<String> items = (List<String>) body.getOrDefault("items", List.of("SKU-ALPHA"));
        double total = ((Number) body.getOrDefault("total", 99.99)).doubleValue();

        Order order = orderService.createOrder(userId, items, total);
        return ResponseEntity.status(HttpStatus.CREATED).body(order);
    }

    @GetMapping("/orders/{orderId}")
    public ResponseEntity<?> getOrder(@PathVariable String orderId) {
        Order order = orderService.getOrder(orderId);
        if (order == null) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of("error", "Order not found", "order_id", orderId));
        }
        return ResponseEntity.ok(order);
    }

    // -------------------------------------------------------------------------
    // Error triggers
    // -------------------------------------------------------------------------
    @PostMapping("/trigger-error")
    public ResponseEntity<?> triggerError(@RequestParam String type) {
        ThreadContext.put("error_type", type);
        log.warn("trigger-error endpoint called");
        ThreadContext.clearAll();

        return switch (type) {
            case "null_pointer"    -> handleNullPointer();
            case "db_timeout"      -> handleDbTimeout();
            case "stack_overflow"  -> handleStackOverflow();
            default -> ResponseEntity.badRequest().body(Map.of(
                    "error", "Unknown error type: " + type,
                    "valid_types", List.of("null_pointer", "db_timeout", "stack_overflow")
            ));
        };
    }

    private ResponseEntity<?> handleNullPointer() {
        try {
            orderService.triggerNullPointer();
            return ResponseEntity.ok(Map.of());
        } catch (NullPointerException e) {
            ThreadContext.put("error_type", "NullPointerException");
            ThreadContext.put("order_id", "ord_null_test");
            log.error("NullPointerException in order processing", e);
            ThreadContext.clearAll();
            return ResponseEntity.status(500).body(Map.of(
                    "error", "NullPointerException: " + e.getMessage(),
                    "error_type", "NullPointerException"
            ));
        }
    }

    private ResponseEntity<?> handleDbTimeout() {
        try {
            orderService.triggerDbTimeout();
            return ResponseEntity.ok(Map.of());
        } catch (DataAccessResourceFailureException e) {
            ThreadContext.put("error_type", "DataAccessResourceFailureException");
            ThreadContext.put("db_host", "postgres-orders.internal");
            ThreadContext.put("pool_size", "10");
            ThreadContext.put("timeout_ms", "30000");
            log.error("DB connection pool exhausted", e);
            ThreadContext.clearAll();
            return ResponseEntity.status(503).body(Map.of(
                    "error", e.getMessage(),
                    "error_type", "DataAccessResourceFailureException"
            ));
        }
    }

    private ResponseEntity<?> handleStackOverflow() {
        try {
            orderService.triggerStackOverflow();
            return ResponseEntity.ok(Map.of());
        } catch (StackOverflowError e) {
            ThreadContext.put("error_type", "StackOverflowError");
            ThreadContext.put("thread", Thread.currentThread().getName());
            log.error("StackOverflowError — infinite recursion detected", e);
            ThreadContext.clearAll();
            return ResponseEntity.status(500).body(Map.of(
                    "error", "StackOverflowError: recursive call depth exceeded JVM limit",
                    "error_type", "StackOverflowError"
            ));
        }
    }
}
