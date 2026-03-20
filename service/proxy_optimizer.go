package service

import (
	"context"
	"fmt"
	"log"
	"net"
	"reflect"
	"runtime"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Locon213/Mimic-Protocol/pkg/client"
	"github.com/Locon213/Mimic-Protocol/pkg/proxy"
)

// ProxyStats holds aggregated proxy statistics from SDK
type ProxyStats struct {
	BytesUp       int64
	BytesDown     int64
	ActiveConns   int32
	TotalConns    int64
	DownloadSpeed int64
	UploadSpeed   int64
}

// ProxyOptimizer provides TCP optimizations and proxy stat aggregation
type ProxyOptimizer struct {
	ctx      context.Context
	cancel   context.CancelFunc
	connPool *ConnectionPool

	// Previous snapshot for speed calculation
	mu        sync.Mutex
	prevUp    int64
	prevDown  int64
	lastCheck time.Time
	lastSpeed ProxyStats
}

// ConnectionPool manages reusable connections
type ConnectionPool struct {
	mu      sync.Mutex
	pools   map[string]*poolEntry
	maxIdle int
	maxAge  time.Duration
}

type poolEntry struct {
	conns       []pooledConn
	maxIdle     int
	idleTimeout time.Duration
}

type pooledConn struct {
	conn      net.Conn
	createdAt time.Time
	lastUsed  time.Time
}

// NewProxyOptimizer creates a new proxy optimizer
func NewProxyOptimizer(ctx context.Context) *ProxyOptimizer {
	ctx, cancel := context.WithCancel(ctx)

	opt := &ProxyOptimizer{
		ctx:       ctx,
		cancel:    cancel,
		connPool:  NewConnectionPool(32, 2*time.Minute),
		lastCheck: time.Now(),
	}

	return opt
}

// OptimizeConn applies TCP optimizations to a connection
func (o *ProxyOptimizer) OptimizeConn(conn net.Conn) net.Conn {
	if tc, ok := conn.(*net.TCPConn); ok {
		_ = tc.SetKeepAlive(true)
		_ = tc.SetKeepAlivePeriod(30 * time.Second)
		_ = tc.SetNoDelay(true)

		if runtime.GOOS != "android" {
			_ = tc.SetReadBuffer(256 * 1024)
			_ = tc.SetWriteBuffer(256 * 1024)
		}
	}
	return conn
}

// GetProxyStats extracts real proxy statistics from the SDK client
// Uses reflection to access the unexported proxies field
func (o *ProxyOptimizer) GetProxyStats(c *client.Client) ProxyStats {
	if c == nil {
		return ProxyStats{}
	}

	var stats ProxyStats

	// Use reflection to access client.proxies field
	v := reflect.ValueOf(c)
	if v.Kind() == reflect.Ptr {
		v = v.Elem()
	}

	proxiesField := v.FieldByName("proxies")
	if !proxiesField.IsValid() {
		log.Printf("[ProxyOpt] Cannot find proxies field via reflection")
		return stats
	}

	// Iterate over proxies slice
	for i := 0; i < proxiesField.Len(); i++ {
		proxyVal := proxiesField.Index(i)

		// Get the concrete value behind the interface
		if proxyVal.Kind() == reflect.Interface {
			proxyVal = proxyVal.Elem()
		}

		// Try to get stats via GetStats() method
		getStatsMethod := proxyVal.MethodByName("GetStats")
		if !getStatsMethod.IsValid() {
			continue
		}

		results := getStatsMethod.Call(nil)
		if len(results) == 0 {
			continue
		}

		statsVal := results[0]
		if statsVal.Kind() == reflect.Ptr {
			statsVal = statsVal.Elem()
		}

		// Read BytesUp
		if f := statsVal.FieldByName("BytesUp"); f.IsValid() {
			if atomicF, ok := f.Addr().Interface().(*atomic.Int64); ok {
				stats.BytesUp += atomicF.Load()
			}
		}

		// Read BytesDown
		if f := statsVal.FieldByName("BytesDown"); f.IsValid() {
			if atomicF, ok := f.Addr().Interface().(*atomic.Int64); ok {
				stats.BytesDown += atomicF.Load()
			}
		}

		// Read ActiveConns
		if f := statsVal.FieldByName("ActiveConns"); f.IsValid() {
			if atomicF, ok := f.Addr().Interface().(*atomic.Int32); ok {
				stats.ActiveConns += atomicF.Load()
			}
		}

		// Read TotalConns
		if f := statsVal.FieldByName("TotalConns"); f.IsValid() {
			if atomicF, ok := f.Addr().Interface().(*atomic.Int64); ok {
				stats.TotalConns += atomicF.Load()
			}
		}
	}

	// Calculate speed (bytes per second)
	o.mu.Lock()
	now := time.Now()
	elapsed := now.Sub(o.lastCheck).Seconds()
	if elapsed >= 1.0 {
		stats.DownloadSpeed = int64(float64(stats.BytesDown-o.prevDown) / elapsed)
		stats.UploadSpeed = int64(float64(stats.BytesUp-o.prevUp) / elapsed)

		// Clamp negative (counter reset)
		if stats.DownloadSpeed < 0 {
			stats.DownloadSpeed = 0
		}
		if stats.UploadSpeed < 0 {
			stats.UploadSpeed = 0
		}

		o.prevDown = stats.BytesDown
		o.prevUp = stats.BytesUp
		o.lastCheck = now
		o.lastSpeed = stats
	} else {
		stats.DownloadSpeed = o.lastSpeed.DownloadSpeed
		stats.UploadSpeed = o.lastSpeed.UploadSpeed
	}
	o.mu.Unlock()

	return stats
}

// GetProxyStatsDirect reads stats from proxy servers directly (for known types)
func GetProxyStatsDirect(proxies []interface{ Close() error }) ProxyStats {
	var stats ProxyStats

	for _, p := range proxies {
		switch srv := p.(type) {
		case *proxy.SOCKS5Server:
			s := srv.GetStats()
			stats.BytesUp += s.BytesUp.Load()
			stats.BytesDown += s.BytesDown.Load()
			stats.ActiveConns += s.ActiveConns.Load()
			stats.TotalConns += s.TotalConns.Load()
		default:
			// Try reflection for HTTP proxy server
			v := reflect.ValueOf(srv)
			getStats := v.MethodByName("GetStats")
			if getStats.IsValid() {
				results := getStats.Call(nil)
				if len(results) > 0 {
					sv := results[0]
					if sv.Kind() == reflect.Ptr {
						sv = sv.Elem()
					}
					if f := sv.FieldByName("BytesUp"); f.IsValid() {
						if af, ok := f.Addr().Interface().(*atomic.Int64); ok {
							stats.BytesUp += af.Load()
						}
					}
					if f := sv.FieldByName("BytesDown"); f.IsValid() {
						if af, ok := f.Addr().Interface().(*atomic.Int64); ok {
							stats.BytesDown += af.Load()
						}
					}
					if f := sv.FieldByName("ActiveConns"); f.IsValid() {
						if af, ok := f.Addr().Interface().(*atomic.Int32); ok {
							stats.ActiveConns += af.Load()
						}
					}
					if f := sv.FieldByName("TotalConns"); f.IsValid() {
						if af, ok := f.Addr().Interface().(*atomic.Int64); ok {
							stats.TotalConns += af.Load()
						}
					}
				}
			}
		}
	}

	return stats
}

// Stop stops the proxy optimizer
func (o *ProxyOptimizer) Stop() {
	o.cancel()
	o.connPool.Close()
}

// ConnectionPool implementation

func NewConnectionPool(maxIdle int, maxAge time.Duration) *ConnectionPool {
	pool := &ConnectionPool{
		pools:   make(map[string]*poolEntry),
		maxIdle: maxIdle,
		maxAge:  maxAge,
	}
	go pool.cleanupLoop()
	return pool
}

func (cp *ConnectionPool) Get(ctx context.Context, network, address string, dial func() (net.Conn, error)) (net.Conn, error) {
	cp.mu.Lock()
	entry, exists := cp.pools[address]
	if exists && len(entry.conns) > 0 {
		pc := entry.conns[len(entry.conns)-1]
		entry.conns = entry.conns[:len(entry.conns)-1]
		cp.mu.Unlock()

		if time.Since(pc.lastUsed) < cp.maxAge {
			return pc.conn, nil
		}
		pc.conn.Close()
	} else {
		cp.mu.Unlock()
	}

	return dial()
}

func (cp *ConnectionPool) Put(address string, conn net.Conn) {
	cp.mu.Lock()
	defer cp.mu.Unlock()

	entry, exists := cp.pools[address]
	if !exists {
		entry = &poolEntry{
			maxIdle:     cp.maxIdle,
			idleTimeout: cp.maxAge,
		}
		cp.pools[address] = entry
	}

	if len(entry.conns) >= entry.maxIdle {
		conn.Close()
		return
	}

	entry.conns = append(entry.conns, pooledConn{
		conn:      conn,
		createdAt: time.Now(),
		lastUsed:  time.Now(),
	})
}

func (cp *ConnectionPool) cleanupLoop() {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		cp.mu.Lock()
		for addr, entry := range cp.pools {
			var active []pooledConn
			for _, pc := range entry.conns {
				if time.Since(pc.lastUsed) < cp.maxAge {
					active = append(active, pc)
				} else {
					pc.conn.Close()
				}
			}
			if len(active) == 0 {
				delete(cp.pools, addr)
			} else {
				entry.conns = active
			}
		}
		cp.mu.Unlock()
	}
}

func (cp *ConnectionPool) Close() {
	cp.mu.Lock()
	defer cp.mu.Unlock()

	for _, entry := range cp.pools {
		for _, pc := range entry.conns {
			pc.conn.Close()
		}
	}
	cp.pools = make(map[string]*poolEntry)
}

func formatBytesProxy(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}
