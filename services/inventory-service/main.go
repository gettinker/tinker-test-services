package main

import (
	"fmt"
	"math/rand"
	"net/http"
	"os"
	"runtime/debug"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

type Item struct {
	ID        string    `json:"id"`
	SKU       string    `json:"sku"`
	Name      string    `json:"name"`
	Quantity  int       `json:"quantity"`
	Warehouse string    `json:"warehouse"`
	UpdatedAt time.Time `json:"updated_at"`
}

type ReserveRequest struct {
	ItemID   string `json:"item_id" binding:"required"`
	Quantity int    `json:"quantity" binding:"required"`
	OrderID  string `json:"order_id" binding:"required"`
}

// ---------------------------------------------------------------------------
// In-memory store
// ---------------------------------------------------------------------------

var (
	mu    sync.RWMutex
	items = map[string]*Item{
		"item_0001": {ID: "item_0001", SKU: "SKU-ALPHA", Name: "Widget Alpha", Quantity: 342, Warehouse: "us-east-1", UpdatedAt: time.Now()},
		"item_0002": {ID: "item_0002", SKU: "SKU-BETA", Name: "Widget Beta", Quantity: 7, Warehouse: "us-west-2", UpdatedAt: time.Now()},
		"item_0003": {ID: "item_0003", SKU: "SKU-GAMMA", Name: "Gadget Gamma", Quantity: 1200, Warehouse: "eu-west-1", UpdatedAt: time.Now()},
		"item_0004": {ID: "item_0004", SKU: "SKU-DELTA", Name: "Gadget Delta", Quantity: 3, Warehouse: "ap-southeast-1", UpdatedAt: time.Now()},
		"item_0005": {ID: "item_0005", SKU: "SKU-EPSILON", Name: "Component Epsilon", Quantity: 89, Warehouse: "us-east-1", UpdatedAt: time.Now()},
	}
	warehouses = []string{"us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1", "sa-east-1"}
)

// ---------------------------------------------------------------------------
// Logger setup
// ---------------------------------------------------------------------------

func setupLogger() {
	zerolog.TimeFieldFormat = time.RFC3339Nano
	zerolog.SetGlobalLevel(zerolog.DebugLevel)
	log.Logger = zerolog.New(os.Stdout).
		With().
		Timestamp().
		Str("service", "inventory-service").
		Logger()
	// Disable Gin's default coloured console logger
	gin.SetMode(gin.ReleaseMode)
}

// ---------------------------------------------------------------------------
// Background log loop
// ---------------------------------------------------------------------------

func backgroundLogLoop() {
	scenarios := []func(){
		logInventoryCheck,
		logStockLowWarning,
		logReorderTriggered,
		logItemReserved,
		logWarehouseSync,
		logReceivingShipment,
		logCycleCount,
	}

	for {
		delay := time.Duration(2000+rand.Intn(3000)) * time.Millisecond
		time.Sleep(delay)
		fn := scenarios[rand.Intn(len(scenarios))]
		func() {
			defer func() {
				if r := recover(); r != nil {
					log.Error().
						Interface("panic", r).
						Str("stack", string(debug.Stack())).
						Msg("panic recovered in background loop")
				}
			}()
			fn()
		}()
	}
}

func randomItemID() string {
	ids := []string{"item_0001", "item_0002", "item_0003", "item_0004", "item_0005"}
	return ids[rand.Intn(len(ids))]
}

func randomWarehouse() string {
	return warehouses[rand.Intn(len(warehouses))]
}

func logInventoryCheck() {
	itemID := randomItemID()
	mu.RLock()
	item := items[itemID]
	mu.RUnlock()
	log.Info().
		Str("item_id", itemID).
		Str("sku", item.SKU).
		Str("warehouse", item.Warehouse).
		Int("quantity", item.Quantity).
		Msg("inventory check")
}

func logStockLowWarning() {
	itemID := randomItemID()
	mu.RLock()
	item := items[itemID]
	mu.RUnlock()
	qty := rand.Intn(8) + 1
	log.Warn().
		Str("item_id", itemID).
		Str("sku", item.SKU).
		Str("warehouse", item.Warehouse).
		Int("quantity", qty).
		Int("reorder_threshold", 10).
		Msg("stock low warning")
}

func logReorderTriggered() {
	itemID := randomItemID()
	mu.RLock()
	item := items[itemID]
	mu.RUnlock()
	log.Info().
		Str("item_id", itemID).
		Str("sku", item.SKU).
		Int("reorder_quantity", rand.Intn(500)+100).
		Str("supplier", "supplier-"+fmt.Sprintf("%02d", rand.Intn(5)+1)).
		Str("expected_delivery", time.Now().Add(time.Duration(rand.Intn(7)+1)*24*time.Hour).Format(time.RFC3339)).
		Msg("reorder triggered")
}

func logItemReserved() {
	log.Info().
		Str("item_id", randomItemID()).
		Str("order_id", "ord_"+uuid.New().String()[:12]).
		Int("quantity_reserved", rand.Intn(5)+1).
		Str("warehouse", randomWarehouse()).
		Int("reservation_ttl_s", 900).
		Msg("item reserved")
}

func logWarehouseSync() {
	log.Info().
		Str("warehouse", randomWarehouse()).
		Int("items_synced", rand.Intn(200)+10).
		Int("discrepancies_found", rand.Intn(3)).
		Int("duration_ms", rand.Intn(500)+50).
		Msg("warehouse sync completed")
}

func logReceivingShipment() {
	log.Info().
		Str("shipment_id", "ship_"+uuid.New().String()[:10]).
		Str("warehouse", randomWarehouse()).
		Int("items_received", rand.Intn(100)+5).
		Str("carrier", []string{"FedEx", "UPS", "DHL", "USPS"}[rand.Intn(4)]).
		Msg("shipment received")
}

func logCycleCount() {
	log.Debug().
		Str("warehouse", randomWarehouse()).
		Int("total_skus", rand.Intn(1000)+100).
		Int("counted_skus", rand.Intn(50)+10).
		Float64("accuracy_pct", 97.0+rand.Float64()*3.0).
		Msg("cycle count in progress")
}

// ---------------------------------------------------------------------------
// HTTP handlers
// ---------------------------------------------------------------------------

func healthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":    "ok",
		"service":   "inventory-service",
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	})
}

func listItemsHandler(c *gin.Context) {
	mu.RLock()
	result := make([]*Item, 0, len(items))
	for _, v := range items {
		result = append(result, v)
	}
	mu.RUnlock()
	log.Info().Int("item_count", len(result)).Msg("items listed")
	c.JSON(http.StatusOK, result)
}

func getItemHandler(c *gin.Context) {
	id := c.Param("id")
	mu.RLock()
	item, ok := items[id]
	mu.RUnlock()
	if !ok {
		log.Warn().Str("item_id", id).Msg("item not found")
		c.JSON(http.StatusNotFound, gin.H{"error": "item not found", "item_id": id})
		return
	}
	log.Info().
		Str("item_id", id).
		Str("sku", item.SKU).
		Str("warehouse", item.Warehouse).
		Int("quantity", item.Quantity).
		Msg("item fetched")
	c.JSON(http.StatusOK, item)
}

func reserveItemHandler(c *gin.Context) {
	var req ReserveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	mu.Lock()
	item, ok := items[req.ItemID]
	if !ok {
		mu.Unlock()
		log.Warn().Str("item_id", req.ItemID).Msg("reserve failed — item not found")
		c.JSON(http.StatusNotFound, gin.H{"error": "item not found"})
		return
	}
	if item.Quantity < req.Quantity {
		mu.Unlock()
		log.Warn().
			Str("item_id", req.ItemID).
			Int("requested", req.Quantity).
			Int("available", item.Quantity).
			Msg("reserve failed — insufficient stock")
		c.JSON(http.StatusConflict, gin.H{"error": "insufficient stock"})
		return
	}
	item.Quantity -= req.Quantity
	item.UpdatedAt = time.Now()
	mu.Unlock()

	log.Info().
		Str("item_id", req.ItemID).
		Str("order_id", req.OrderID).
		Int("quantity_reserved", req.Quantity).
		Int("remaining_quantity", item.Quantity).
		Msg("item reserved")

	c.JSON(http.StatusOK, gin.H{
		"item_id":            req.ItemID,
		"order_id":           req.OrderID,
		"quantity_reserved":  req.Quantity,
		"remaining_quantity": item.Quantity,
	})
}

// ---------------------------------------------------------------------------
// Error trigger handlers
// ---------------------------------------------------------------------------

func triggerErrorHandler(c *gin.Context) {
	errorType := c.Query("type")
	log.Warn().Str("error_type", errorType).Msg("trigger-error endpoint called")

	switch errorType {
	case "null_pointer":
		triggerNilPointer(c)
	case "index_out_of_bounds":
		triggerIndexOutOfBounds(c)
	case "db_timeout":
		triggerDBTimeout(c)
	default:
		c.JSON(http.StatusBadRequest, gin.H{
			"error":       fmt.Sprintf("unknown error type: %s", errorType),
			"valid_types": []string{"null_pointer", "index_out_of_bounds", "db_timeout"},
		})
	}
}

func triggerNilPointer(c *gin.Context) {
	defer func() {
		if r := recover(); r != nil {
			stack := debug.Stack()
			log.Error().
				Interface("panic", r).
				Str("stack_trace", string(stack)).
				Str("error_type", "nil_pointer_dereference").
				Str("item_id", "item_nil_test").
				Str("warehouse", "us-east-1").
				Msg("panic: nil pointer dereference in inventory lookup")
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":      fmt.Sprintf("panic: %v", r),
				"error_type": "nil_pointer_dereference",
			})
		}
	}()

	// Simulate a nil item returned from a failed DB lookup
	var item *Item
	// This will panic: runtime error: invalid memory address or nil pointer dereference
	_ = item.Quantity
}

func triggerIndexOutOfBounds(c *gin.Context) {
	defer func() {
		if r := recover(); r != nil {
			stack := debug.Stack()
			log.Error().
				Interface("panic", r).
				Str("stack_trace", string(stack)).
				Str("error_type", "index_out_of_range").
				Str("operation", "batch_item_lookup").
				Msg("panic: runtime error: index out of range")
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":      fmt.Sprintf("panic: %v", r),
				"error_type": "index_out_of_range",
			})
		}
	}()

	// Intentional index out of bounds
	batch := []string{"item_0001", "item_0002"}
	_ = batch[10] // panic: runtime error: index out of range [10] with length 2
}

func simulateDBQuery(depth int) ([]Item, error) {
	if depth == 0 {
		// Simulate timeout
		return nil, fmt.Errorf(
			"context deadline exceeded: database query timed out after 5000ms "+
				"(host=postgres-inventory.internal:5432, query=SELECT * FROM inventory "+
				"WHERE warehouse=$1 AND quantity < $2)",
		)
	}
	return simulateDBQuery(depth - 1)
}

func triggerDBTimeout(c *gin.Context) {
	log.Warn().
		Str("db_host", "postgres-inventory.internal").
		Int("timeout_ms", 5000).
		Str("query", "SELECT * FROM inventory WHERE warehouse=$1 AND quantity < $2").
		Msg("database query timeout — connection pool exhausted")

	var result []Item
var err error
for i := 0; i < 3; i++ {
	result, err = simulateDBQuery(4)
	if err == nil {
		break
	}
	time.Sleep(2 * time.Second)
}
	if err != nil {
		log.Error().
			Err(err).
			Str("error_type", "db_timeout").
			Str("db_host", "postgres-inventory.internal").
			Int("pool_size", 10).
			Int("active_connections", 10).
			Int("waiting_goroutines", 18).
			Msg("database timeout error in inventory service")
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":      err.Error(),
			"error_type": "db_timeout",
		})
		return
	}
	c.JSON(http.StatusOK, result)
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

func main() {
	setupLogger()
	log.Info().Int("port", 8004).Msg("inventory-service starting up")

	go backgroundLogLoop()

	router := gin.New()

	// Request logger middleware
	router.Use(func(c *gin.Context) {
		start := time.Now()
		c.Next()
		log.Info().
			Str("method", c.Request.Method).
			Str("path", c.Request.URL.Path).
			Int("status", c.Writer.Status()).
			Int64("latency_ms", time.Since(start).Milliseconds()).
			Str("client_ip", c.ClientIP()).
			Msg("http request")
	})

	// Recovery middleware — logs panics that slip through endpoint-level defers
	router.Use(gin.CustomRecovery(func(c *gin.Context, recovered interface{}) {
		log.Error().
			Interface("panic", recovered).
			Str("stack_trace", string(debug.Stack())).
			Str("path", c.Request.URL.Path).
			Msg("unhandled panic recovered by middleware")
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("internal server error: %v", recovered),
		})
	}))

	router.GET("/health", healthHandler)
	router.GET("/items", listItemsHandler)
	router.GET("/items/:id", getItemHandler)
	router.POST("/reserve", reserveItemHandler)
	router.POST("/trigger-error", triggerErrorHandler)

	if err := router.Run(":8004"); err != nil {
		log.Fatal().Err(err).Msg("failed to start server")
	}
}
