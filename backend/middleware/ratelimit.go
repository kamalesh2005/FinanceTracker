package middleware

import (
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// RateLimit returns middleware that allows at most `limit` requests per `window`
// from each client IP. Exceeded requests get 429 + Retry-After.
func RateLimit(limit int, window time.Duration) gin.HandlerFunc {
	if limit <= 0 {
		limit = 1
	}
	if window <= 0 {
		window = time.Minute
	}

	var (
		mu   sync.Mutex
		hits = map[string][]time.Time{}
	)

	go func() {
		ticker := time.NewTicker(window)
		defer ticker.Stop()
		for range ticker.C {
			mu.Lock()
			cutoff := time.Now().Add(-window)
			for key, times := range hits {
				kept := times[:0]
				for _, t := range times {
					if t.After(cutoff) {
						kept = append(kept, t)
					}
				}
				if len(kept) == 0 {
					delete(hits, key)
				} else {
					hits[key] = kept
				}
			}
			mu.Unlock()
		}
	}()

	return func(c *gin.Context) {
		ip := c.ClientIP()
		now := time.Now()
		cutoff := now.Add(-window)

		mu.Lock()
		times := hits[ip]
		kept := times[:0]
		for _, t := range times {
			if t.After(cutoff) {
				kept = append(kept, t)
			}
		}
		if len(kept) >= limit {
			oldest := kept[0]
			retryAfter := int(oldest.Add(window).Sub(now).Seconds()) + 1
			if retryAfter < 1 {
				retryAfter = 1
			}
			hits[ip] = kept
			mu.Unlock()
			c.Header("Retry-After", strconv.Itoa(retryAfter))
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "too many attempts, please try again later",
			})
			return
		}
		hits[ip] = append(kept, now)
		mu.Unlock()
		c.Next()
	}
}
