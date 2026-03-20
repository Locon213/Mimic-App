package service

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Locon213/Mimic-App/compression"
	"github.com/Locon213/Mimic-Protocol/pkg/client"
	"github.com/Locon213/Mimic-Protocol/pkg/config"
)

// VpnService provides VPN service functionality

type VpnService struct {
	mu              sync.RWMutex
	client          *client.Client
	ctx             context.Context
	cancel          context.CancelFunc
	mode            string
	lastStats       client.NetworkStats
	statsCallback   func(client.NetworkStats)
	serverName      string
	serverAddress   string
	statsTicker     *time.Ticker
	statsTickerDone chan struct{}
	isRunning       atomic.Bool
	compressor      *compression.Compressor
	proxyOptimizer  *ProxyOptimizer
}

func NewVpnService() *VpnService {
	return &VpnService{}
}

// NewVpnServiceWithCompression creates a new VPN service with compression support
func NewVpnServiceWithCompression(compressionEnabled bool, compressionLevel int) (*VpnService, error) {
	if !compressionEnabled {
		return &VpnService{}, nil
	}

	cfg := compression.CompressorConfig{
		Level:   compressionLevel,
		MinSize: 64,
	}
	compressor, err := compression.NewCompressor(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create compressor: %w", err)
	}

	return &VpnService{
		compressor: compressor,
	}, nil
}

func (v *VpnService) StartService(serverUrl string, mode string) error {
	// Check if already running
	if v.isRunning.Load() {
		return errors.New("service is already running")
	}

	v.mu.Lock()
	defer v.mu.Unlock()

	if serverUrl == "" {
		return errors.New("please enter a server URL")
	}

	cfg, err := config.ParseMimicURL(serverUrl)
	if err != nil {
		return fmt.Errorf("failed to parse server URL: %w", err)
	}

	// Extract server name from URL (after #)
	v.serverName = v.extractServerName(serverUrl)
	v.serverAddress = cfg.Server

	// Always use explicit local proxies for the client.
	cfg.Proxies = []config.ProxyConfig{
		{Type: "socks5", Port: 1080},
		{Type: "http", Port: 1081},
	}
	cfg.DNS = "1.1.1.1:53"

	// Configure buffer optimization for high-speed networks
	if cfg.Buffer.RelayBufferSize <= 0 {
		cfg.Buffer.RelayBufferSize = 128 * 1024 // 128KB
	}
	if cfg.Buffer.ReadBufferSize <= 0 {
		cfg.Buffer.ReadBufferSize = 64 * 1024 // 64KB
	}

	mimicClient, err := client.NewClient(cfg)
	if err != nil {
		return fmt.Errorf("failed to create client: %w", err)
	}

	// Initialize context first
	v.ctx, v.cancel = context.WithCancel(context.Background())
	v.mode = mode
	v.client = mimicClient
	v.isRunning.Store(true)

	// Initialize proxy optimizer for better performance
	v.proxyOptimizer = NewProxyOptimizer(v.ctx)

	// Set traffic callback for real-time stats
	// Use a wrapper to prevent race conditions
	mimicClient.SetTrafficCallback(func(stats client.NetworkStats) {
		// Aggregate real proxy stats
		if v.proxyOptimizer != nil {
			proxyStats := v.proxyOptimizer.GetProxyStats(mimicClient)

			// Use real proxy data instead of empty SDK stats
			if proxyStats.DownloadSpeed > 0 || proxyStats.UploadSpeed > 0 ||
				proxyStats.BytesDown > 0 || proxyStats.BytesUp > 0 {
				stats.TotalDownload = proxyStats.BytesDown
				stats.TotalUpload = proxyStats.BytesUp
				stats.DownloadSpeed = proxyStats.DownloadSpeed
				stats.UploadSpeed = proxyStats.UploadSpeed
			}
		}

		// Safely update stats
		v.mu.Lock()
		v.lastStats = stats
		v.mu.Unlock()

		// Call external callback if set
		v.mu.RLock()
		callback := v.statsCallback
		v.mu.RUnlock()

		if callback != nil {
			// Recover from potential panic in callback
			defer func() {
				if r := recover(); r != nil {
					log.Printf("Panic in stats callback: %v\n", r)
				}
			}()
			callback(stats)
		}
	})

	// Start client connection
	if err := v.client.Start(v.ctx); err != nil {
		v.cleanup()
		return fmt.Errorf("failed to start client: %w", err)
	}

	// Start proxies
	if err := v.client.StartProxies(); err != nil {
		v.client.Stop()
		v.cleanup()
		return fmt.Errorf("failed to start proxies: %w", err)
	}

	// Start TUN if needed
	if strings.Contains(mode, "TUN") {
		log.Println("TUN mode selected. Starting tun2socks...")
		ConfigureTunRemoteAddress(v.serverAddress)
		err := StartTun2Socks()
		if err != nil {
			log.Printf("Failed to start TUN network: %v\n", err)
			v.client.Stop()
			v.cleanup()
			return errors.New("failed to start TUN network (try running as Administrator): " + err.Error())
		}
	}

	// Initialize stats ticker
	v.statsTickerDone = make(chan struct{})
	v.statsTicker = time.NewTicker(1 * time.Second)
	go v.statsLoop()

	// Log compression status
	if v.compressor != nil {
		log.Printf("✅ Service started successfully, connected to %s (compression enabled)", v.serverAddress)
	} else {
		log.Printf("✅ Service started successfully, connected to %s", v.serverAddress)
	}
	return nil
}

func (v *VpnService) StopService() {
	// Stop TUN first
	StopTun2Socks()

	v.mu.Lock()
	defer v.mu.Unlock()

	v.cleanup()
}

// GetCompressor returns the compressor instance
func (v *VpnService) GetCompressor() *compression.Compressor {
	v.mu.RLock()
	defer v.mu.RUnlock()
	return v.compressor
}

// SetCompressor sets the compressor instance
func (v *VpnService) SetCompressor(compressor *compression.Compressor) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.compressor = compressor
}

// cleanup performs internal cleanup of resources
func (v *VpnService) cleanup() {
	// Stop stats ticker
	if v.statsTicker != nil {
		v.statsTicker.Stop()
		v.statsTicker = nil
	}
	if v.statsTickerDone != nil {
		close(v.statsTickerDone)
		v.statsTickerDone = nil
	}

	// Stop proxy optimizer
	if v.proxyOptimizer != nil {
		v.proxyOptimizer.Stop()
		v.proxyOptimizer = nil
	}

	// Cancel context
	if v.cancel != nil {
		v.cancel()
		v.cancel = nil
	}

	// Stop client
	if v.client != nil {
		v.client.Stop()
		v.client = nil
	}

	// Close compressor
	if v.compressor != nil {
		v.compressor.Close()
		v.compressor = nil
	}

	v.isRunning.Store(false)
}

// statsLoop periodically processes stats
func (v *VpnService) statsLoop() {
	for {
		select {
		case <-v.statsTicker.C:
			// Periodic stats processing if needed
		case <-v.statsTickerDone:
			return
		}
	}
}

// Stats returns current network statistics
func (v *VpnService) Stats() client.NetworkStats {
	v.mu.RLock()
	defer v.mu.RUnlock()
	return v.lastStats
}

// GetConnectionStatus returns current connection status
func (v *VpnService) GetConnectionStatus() string {
	v.mu.RLock()
	defer v.mu.RUnlock()

	if v.client == nil {
		return "disconnected"
	}
	status := v.client.GetConnectionStatus()
	return string(status)
}

// IsConnected returns true if client is connected
func (v *VpnService) IsConnected() bool {
	v.mu.RLock()
	defer v.mu.RUnlock()

	if v.client == nil {
		return false
	}
	return v.client.IsConnected()
}

// GetSessionInfo returns current session info
func (v *VpnService) GetSessionInfo() *client.SessionInfo {
	v.mu.RLock()
	defer v.mu.RUnlock()

	if v.client == nil {
		return nil
	}
	return v.client.GetSessionInfo()
}

// GetCurrentDomain returns current masking domain (SNI)
func (v *VpnService) GetCurrentDomain() string {
	v.mu.RLock()
	defer v.mu.RUnlock()

	if v.client == nil {
		return ""
	}
	return v.client.GetCurrentDomain()
}

// Reconnect performs reconnection to the server
func (v *VpnService) Reconnect() error {
	v.mu.RLock()
	defer v.mu.RUnlock()

	if v.client == nil {
		return errors.New("client not initialized")
	}
	return v.client.Reconnect(v.ctx)
}

// GetVersion returns SDK version
func (v *VpnService) GetVersion() string {
	v.mu.RLock()
	defer v.mu.RUnlock()

	if v.client == nil {
		return "N/A"
	}
	return v.client.GetVersion()
}

// SetStatsCallback sets a callback for stats updates
func (v *VpnService) SetStatsCallback(callback func(client.NetworkStats)) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.statsCallback = callback
}

// Legacy Stats method for backward compatibility
func (v *VpnService) StatsLegacy() (uint64, uint64) {
	stats := v.Stats()
	return uint64(stats.TotalUpload), uint64(stats.TotalDownload)
}

// extractServerName extracts server name from mimic URL (after #)
func (v *VpnService) extractServerName(url string) string {
	parts := strings.Split(url, "#")
	if len(parts) > 1 {
		return parts[1]
	}
	// Fallback: extract from host
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

// formatBytes formats bytes to human readable string
func formatBytes(b uint64) string {
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
