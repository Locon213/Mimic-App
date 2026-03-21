// Package mobile provides a Go Mobile compatible interface for Mimic Protocol.
// This package is designed to be used with gomobile bind for iOS and Android.
package mobile

import (
	"context"
	"fmt"
	"runtime"
	"runtime/debug"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Locon213/Mimic-App/config"
	"github.com/Locon213/Mimic-App/service"
	"github.com/Locon213/Mimic-Protocol/pkg/client"
	mimicconfig "github.com/Locon213/Mimic-Protocol/pkg/config"
)

// ConnectionStatus represents the current connection state
type ConnectionStatus int32

const (
	StatusDisconnected ConnectionStatus = iota
	StatusConnecting
	StatusConnected
	StatusReconnecting
)

// String returns the string representation of ConnectionStatus
func (s ConnectionStatus) String() string {
	switch s {
	case StatusDisconnected:
		return "disconnected"
	case StatusConnecting:
		return "connecting"
	case StatusConnected:
		return "connected"
	case StatusReconnecting:
		return "reconnecting"
	default:
		return "unknown"
	}
}

// NetworkStats holds network statistics for mobile consumption
type NetworkStats struct {
	DownloadSpeed int64 // bytes per second
	UploadSpeed   int64 // bytes per second
	Ping          int64 // milliseconds
	TotalDownload int64 // total bytes received
	TotalUpload   int64 // total bytes sent
	LastUpdated   int64 // unix timestamp
}

// MimicClient is a mobile-friendly wrapper around the Mimic SDK client
type MimicClient struct {
	client      *client.Client
	ctx         context.Context
	cancel      context.CancelFunc
	mu          sync.RWMutex
	status      atomic.Int32
	serverName  string
	serverURL   string
	mode        string // "Proxy" or "TUN"
	statsTicker *time.Ticker
	statsDone   chan struct{}
	lastStats   NetworkStats
	callback    func(NetworkStats)
	configMgr   *config.ConfigManager
	configPath  string
}

// NewMimicClient creates a new Mimic client instance
func NewMimicClient() *MimicClient {
	return &MimicClient{
		status: atomic.Int32{},
	}
}

// GetVersion returns the SDK version
func (m *MimicClient) GetVersion() string {
	if m.client == nil {
		return "0.0.0"
	}
	return m.client.GetVersion()
}

// Connect establishes connection to the Mimic server
func (m *MimicClient) Connect(serverURL, mode string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.status.Load() == int32(StatusConnected) {
		return fmt.Errorf("already connected")
	}

	if serverURL == "" {
		return fmt.Errorf("server URL is required")
	}

	m.status.Store(int32(StatusConnecting))
	m.serverURL = serverURL
	m.mode = mode

	// Parse server URL
	cfg, err := mimicconfig.ParseMimicURL(serverURL)
	if err != nil {
		m.status.Store(int32(StatusDisconnected))
		return fmt.Errorf("failed to parse URL: %w", err)
	}

	// Extract server name from URL fragment
	m.serverName = extractServerName(serverURL)

	// Configure proxies
	cfg.Proxies = []mimicconfig.ProxyConfig{
		{Type: "socks5", Port: 1080},
		{Type: "http", Port: 1081},
	}
	cfg.DNS = "1.1.1.1:53"

	// Configure buffer optimization
	if cfg.Buffer.RelayBufferSize <= 0 || cfg.Buffer.RelayBufferSize == 128*1024 {
		cfg.Buffer.RelayBufferSize = 4 * 1024 * 1024 // 4MB
	}
	if cfg.Buffer.ReadBufferSize <= 0 || cfg.Buffer.ReadBufferSize == 64*1024 {
		cfg.Buffer.ReadBufferSize = 1 * 1024 * 1024 // 1MB
	}
	cfg.Buffer.EnableOptimizedBuffers = true

	// Tune Go Garbage Collector for high-speed streaming throughput
	debug.SetGCPercent(150)

	// Create client
	mimicClient, err := client.NewClient(cfg)
	if err != nil {
		m.status.Store(int32(StatusDisconnected))
		return fmt.Errorf("failed to create client: %w", err)
	}

	m.client = mimicClient
	m.ctx, m.cancel = context.WithCancel(context.Background())

	// Set traffic callback with real MTP stats
	m.client.SetTrafficCallback(func(stats client.NetworkStats) {

		m.mu.Lock()
		m.lastStats = NetworkStats{
			DownloadSpeed: stats.DownloadSpeed,
			UploadSpeed:   stats.UploadSpeed,
			Ping:          stats.Ping,
			TotalDownload: stats.TotalDownload,
			TotalUpload:   stats.TotalUpload,
			LastUpdated:   time.Now().Unix(),
		}
		m.mu.Unlock()

		if m.callback != nil {
			m.callback(m.lastStats)
		}
	})

	// Start client
	if err := m.client.Start(m.ctx); err != nil {
		m.status.Store(int32(StatusDisconnected))
		return fmt.Errorf("failed to start client: %w", err)
	}

	// Start proxies
	if err := m.client.StartProxies(); err != nil {
		m.client.Stop()
		m.status.Store(int32(StatusDisconnected))
		return fmt.Errorf("failed to start proxies: %w", err)
	}

	// Start TUN if needed
	if strings.Contains(mode, "TUN") && runtime.GOOS != "android" {
		service.ConfigureTunRemoteAddress(cfg.Server)
		if err := service.StartTun2Socks(); err != nil {
			m.client.Stop()
			m.status.Store(int32(StatusDisconnected))
			return fmt.Errorf("failed to start TUN: %w", err)
		}
	}

	m.status.Store(int32(StatusConnected))

	// Start stats ticker
	m.statsDone = make(chan struct{})
	m.statsTicker = time.NewTicker(1 * time.Second)
	go m.statsLoop()

	return nil
}

// StartTun attaches tun2socks to an already-created TUN file descriptor.
// Android VpnService owns the TUN interface and passes the fd here.
func (m *MimicClient) StartTun(fd, mtu int) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.client == nil {
		return fmt.Errorf("client is not connected")
	}

	if !strings.Contains(m.mode, "TUN") {
		return fmt.Errorf("TUN mode is not active")
	}

	if err := service.StartTun2SocksFromFD(fd, mtu); err != nil {
		return fmt.Errorf("failed to start TUN from fd: %w", err)
	}

	return nil
}

// Disconnect stops the connection
func (m *MimicClient) Disconnect() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.cancel != nil {
		m.cancel()
	}

	// Stop stats ticker
	if m.statsTicker != nil {
		m.statsTicker.Stop()
	}
	if m.statsDone != nil {
		close(m.statsDone)
		m.statsDone = nil
	}

	// Stop TUN
	service.StopTun2Socks()

	// Stop client
	if m.client != nil {
		m.client.Stop()
		m.client = nil
	}

	m.status.Store(int32(StatusDisconnected))
}

// IsConnected returns true if currently connected
func (m *MimicClient) IsConnected() bool {
	return m.status.Load() == int32(StatusConnected)
}

// GetStatus returns current connection status
func (m *MimicClient) GetStatus() ConnectionStatus {
	return ConnectionStatus(m.status.Load())
}

// GetStatusString returns current connection status as string
func (m *MimicClient) GetStatusString() string {
	return ConnectionStatus(m.status.Load()).String()
}

// GetStats returns current network statistics
func (m *MimicClient) GetStats() NetworkStats {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.lastStats
}

// GetDownloadSpeed returns the current download speed in bytes per second.
func (m *MimicClient) GetDownloadSpeed() int64 {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.lastStats.DownloadSpeed
}

// GetUploadSpeed returns the current upload speed in bytes per second.
func (m *MimicClient) GetUploadSpeed() int64 {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.lastStats.UploadSpeed
}

// GetPing returns the current ping in milliseconds.
func (m *MimicClient) GetPing() int64 {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.lastStats.Ping
}

// GetTotalDownload returns the total downloaded bytes.
func (m *MimicClient) GetTotalDownload() int64 {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.lastStats.TotalDownload
}

// GetTotalUpload returns the total uploaded bytes.
func (m *MimicClient) GetTotalUpload() int64 {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.lastStats.TotalUpload
}

// GetLastUpdated returns the last stats update as a Unix timestamp.
func (m *MimicClient) GetLastUpdated() int64 {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.lastStats.LastUpdated
}

// GetServerName returns the current server name
func (m *MimicClient) GetServerName() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.serverName
}

// GetServerURL returns the current server URL
func (m *MimicClient) GetServerURL() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.serverURL
}

// SetStatsCallback sets a callback for stats updates
func (m *MimicClient) SetStatsCallback(cb func(NetworkStats)) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.callback = cb
}

// Reconnect performs reconnection
func (m *MimicClient) Reconnect() error {
	m.Disconnect()
	time.Sleep(100 * time.Millisecond)
	return m.Connect(m.serverURL, m.mode)
}

// statsLoop periodically updates statistics
func (m *MimicClient) statsLoop() {
	for {
		select {
		case <-m.statsTicker.C:
			if m.callback != nil {
				m.mu.RLock()
				stats := m.lastStats
				m.mu.RUnlock()
				m.callback(stats)
			}
		case <-m.statsDone:
			return
		}
	}
}

// extractServerName extracts server name from mimic URL
func extractServerName(url string) string {
	parts := strings.Split(url, "#")
	if len(parts) > 1 {
		return parts[1]
	}
	parts = strings.Split(url, "@")
	if len(parts) > 1 {
		hostPart := parts[1]
		endIdx := strings.IndexAny(hostPart, "?/")
		if endIdx == -1 {
			endIdx = len(hostPart)
		}
		return hostPart[:endIdx]
	}
	return "Unknown Server"
}

// FormatBytes formats bytes to human readable string
func FormatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

// FormatBytesPerSecond formats bytes per second to human readable string
func FormatBytesPerSecond(bytesPerSec int64) string {
	return FormatBytes(bytesPerSec) + "/s"
}
