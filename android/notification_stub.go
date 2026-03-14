//go:build !android

package android

import "sync"

// NotificationService is a stub for non-Android platforms
type NotificationService struct {
	mu             sync.RWMutex
	notificationID int
	channelID      string
	channelName    string
	isActive       bool
	currentTitle   string
	currentContent string
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

// Init initializes the notification service (no-op on non-Android)
func (ns *NotificationService) Init() {}

// ShowConnected shows a persistent notification when VPN is connected (no-op on non-Android)
func (ns *NotificationService) ShowConnected(serverName, serverAddress, downloadSpeed, uploadSpeed string) {
}

// Update updates the notification with new speed stats (no-op on non-Android)
func (ns *NotificationService) Update(serverName, downloadSpeed, uploadSpeed string) {
}

// Hide removes the notification (no-op on non-Android)
func (ns *NotificationService) Hide() {
}

// IsActive returns true if notification is currently showing
func (ns *NotificationService) IsActive() bool {
	return false
}

// SetNotificationID sets a custom notification ID
func (ns *NotificationService) SetNotificationID(id int) {
}

// RequestIgnoreBatteryOptimizations requests battery optimization exemption (no-op on non-Android)
func RequestIgnoreBatteryOptimizations() {
}

// IsIgnoringBatteryOptimizations checks if battery optimizations are disabled
func IsIgnoringBatteryOptimizations() bool {
	return false
}
