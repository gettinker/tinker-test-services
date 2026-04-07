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
	"golang.org/x/net/context"
)

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

// ... [rest of the code remains unchanged] ...

func simulateDBQuery(ctx context.Context, depth int) ([]Item, error) {
	if depth == 0 {
		// Simulate timeout
		select {
		case <-ctx.Done():
			return nil, fmt.Errorf("context deadline exceeded: database query timed out after 5000ms (host=postgres-inventory.internal:5432, query=SELECT * FROM inventory WHERE warehouse=$1 AND quantity < $2)")
		case <-time.After(5000 * time.Millisecond):
			return nil, fmt.Errorf("context deadline exceeded: database query timed out after 5000ms (host=postgres-inventory.internal:5432, query=SELECT * FROM inventory WHERE warehouse=$1 AND quantity < $2)")
		}
	}
	return simulateDBQuery(ctx, depth-1)
}

func triggerDBTimeout(c *gin.Context) {
	log.Warn().
		Str("db_host", "postgres-inventory.internal").
		Int("timeout_ms", 5000).
		Str("query", "SELECT * FROM inventory WHERE warehouse=$1 AND quantity < $2").
		Msg("database query timeout — connection pool exhausted")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	result, err := simulateDBQuery(ctx, 4)
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