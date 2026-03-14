package service

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/Locon213/Mimic-App/android"
	"github.com/Locon213/Mimic-Protocol/pkg/client"
	"github.com/Locon213/Mimic-Protocol/pkg/config"
)

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
	notifService    *android.NotificationService
	statsTicker     *time.Ticker
	statsTickerDone chan struct{}
}

func NewVpnService() *VpnService {
	return &VpnService{
		notifService: android.GetNotificationService(),
	}
}

func (v *VpnService) StartService(serverUrl string, mode string) error {
	v.mu.Lock()
	defer v.mu.Unlock()

	if serverUrl == "" {
		return errors.New("please enter a server URL")
	}

	cfg, err := config.ParseMimicURL(serverUrl)
	if err != nil {
		return err
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

	mimicClient, err := client.NewClient(cfg)
	if err != nil {
		return err
	}

	v.client = mimicClient
	v.ctx, v.cancel = context.WithCancel(context.Background())
	v.mode = mode

	// Set traffic callback for real-time stats
	mimicClient.SetTrafficCallback(func(stats client.NetworkStats) {
		v.mu.Lock()
		v.lastStats = stats
		v.mu.Unlock()

		// Update Android notification with new stats
		v.updateNotification(stats)

		if v.statsCallback != nil {
			v.statsCallback(stats)
		}
	})

	if err := v.client.Start(v.ctx); err != nil {
		return err
	}

	if err := v.client.StartProxies(); err != nil {
		v.client.Stop()
		return err
	}

	if strings.Contains(mode, "TUN") {
		log.Println("TUN mode selected. Starting tun2socks...")
		err := StartTun2Socks()
		if err != nil {
			log.Printf("Failed to start TUN network: %v\n", err)
			return errors.New("failed to start TUN network (try running as Administrator): " + err.Error())
		}
	}

	// Show Android notification after successful connection
	v.showConnectedNotification(v.lastStats)

	return nil
}

func (v *VpnService) StopService() {
	StopTun2Socks()
	v.mu.Lock()
	defer v.mu.Unlock()

	// Stop stats ticker
	if v.statsTicker != nil {
		v.statsTicker.Stop()
		v.statsTicker = nil
	}
	if v.statsTickerDone != nil {
		close(v.statsTickerDone)
		v.statsTickerDone = nil
	}

	// Hide Android notification
	if v.notifService != nil {
		v.notifService.Hide()
	}

	if v.client != nil {
		v.client.Stop()
		v.client = nil
	}
	if v.cancel != nil {
		v.cancel()
		v.cancel = nil
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

// showConnectedNotification shows the Android system notification
func (v *VpnService) showConnectedNotification(stats client.NetworkStats) {
	if v.notifService == nil {
		return
	}

	downloadSpeed := formatBytes(uint64(stats.DownloadSpeed)) + "/s"
	uploadSpeed := formatBytes(uint64(stats.UploadSpeed)) + "/s"

	v.notifService.ShowConnected(
		v.serverName,
		v.serverAddress,
		downloadSpeed,
		uploadSpeed,
	)
}

// updateNotification updates the Android notification with new stats
func (v *VpnService) updateNotification(stats client.NetworkStats) {
	if v.notifService == nil {
		return
	}

	downloadSpeed := formatBytes(uint64(stats.DownloadSpeed)) + "/s"
	uploadSpeed := formatBytes(uint64(stats.UploadSpeed)) + "/s"

	v.notifService.Update(v.serverName, downloadSpeed, uploadSpeed)
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
