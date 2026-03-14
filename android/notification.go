//go:build android

package android

import (
	"fmt"
	"sync"

	"fyne.io/fyne/v2"
)

// NotificationService handles Android system notifications for VPN status
type NotificationService struct {
	mu             sync.RWMutex
	notificationID int
	channelID      string
	channelName    string
	isActive       bool
	currentTitle   string
	currentContent string
	downloadSpeed  string
	uploadSpeed    string
	serverName     string
}

var (
	notifInstance *NotificationService
	notifOnce     sync.Once
)

// GetNotificationService returns the singleton notification service instance
func GetNotificationService() *NotificationService {
	notifOnce.Do(func() {
		notifInstance = &NotificationService{
			notificationID: 1001,
			channelID:      "mimic_vpn_service",
			channelName:    "Mimic VPN Service",
			isActive:       false,
		}
	})
	return notifInstance
}

// Init initializes the notification service
func (ns *NotificationService) Init() {
	// Fyne handles notification channel creation automatically on Android
}

// ShowConnected shows a persistent notification when VPN is connected
// This notification cannot be dismissed by the user (ongoing)
func (ns *NotificationService) ShowConnected(serverName, serverAddress, downloadSpeed, uploadSpeed string) {
	ns.mu.Lock()
	ns.serverName = serverName
	ns.downloadSpeed = downloadSpeed
	ns.uploadSpeed = uploadSpeed
	ns.mu.Unlock()

	ns.showNotification()
}

// Update updates the notification with new speed stats
func (ns *NotificationService) Update(serverName, downloadSpeed, uploadSpeed string) {
	ns.mu.Lock()
	ns.serverName = serverName
	ns.downloadSpeed = downloadSpeed
	ns.uploadSpeed = uploadSpeed
	ns.mu.Unlock()

	if ns.isActive {
		ns.showNotification()
	}
}

// showNotification creates or updates the system notification
func (ns *NotificationService) showNotification() {
	ns.mu.Lock()
	defer ns.mu.Unlock()

	title := "🔒 Mimic VPN - Connected"
	content := fmt.Sprintf("Server: %s\n↓ %s  ↑ %s", ns.serverName, ns.downloadSpeed, ns.uploadSpeed)

	ns.currentTitle = title
	ns.currentContent = content

	// Use Fyne's mobile notification API
	// Note: For persistent foreground service notification, we need native Android code
	// This is a simplified version using Fyne's notification
	n := &fyne.Notification{
		Title:   title,
		Content: content,
	}

	// Send notification
	fyne.CurrentApp().SendNotification(n)

	ns.isActive = true
}

// Hide removes the notification
func (ns *NotificationService) Hide() {
	ns.mu.Lock()
	defer ns.mu.Unlock()

	ns.isActive = false
	ns.currentTitle = ""
	ns.currentContent = ""
}

// IsActive returns true if notification is currently showing
func (ns *NotificationService) IsActive() bool {
	ns.mu.RLock()
	defer ns.mu.RUnlock()
	return ns.isActive
}

// SetNotificationID sets a custom notification ID
func (ns *NotificationService) SetNotificationID(id int) {
	ns.mu.Lock()
	defer ns.mu.Unlock()
	ns.notificationID = id
}

// RequestIgnoreBatteryOptimizations requests battery optimization exemption
// This is needed for persistent VPN service
func RequestIgnoreBatteryOptimizations() {
	// This requires native Android code integration
	// Can be implemented via gomobile bind or Fyne Android backend
}

// IsIgnoringBatteryOptimizations checks if battery optimizations are disabled
func IsIgnoringBatteryOptimizations() bool {
	// This requires native Android code integration
	return false
}
