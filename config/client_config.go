// Package config provides client.yaml configuration parsing and validation.
package config

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/goccy/go-yaml"
)

// ClientConfig represents the full client.yaml configuration structure
type ClientConfig struct {
	// Required fields
	Server string `yaml:"server" validate:"required"`
	UUID   string `yaml:"uuid" validate:"required"`

	// Optional fields
	Domains       []DomainConfig          `yaml:"domains,omitempty"`
	Transport     string                  `yaml:"transport,omitempty"`
	LocalPort     int                     `yaml:"local_port,omitempty"`
	DNS           string                  `yaml:"dns,omitempty"`
	Compression   *CompressionConfig      `yaml:"compression,omitempty"`
	CustomPresets map[string]PresetConfig `yaml:"custom_presets,omitempty"`
	Proxies       []ProxyConfig           `yaml:"proxies,omitempty"`
	Routing       *RoutingConfig          `yaml:"routing,omitempty"`
	Settings      *SettingsConfig         `yaml:"settings,omitempty"`
}

// DomainConfig represents a domain configuration for mimicry
type DomainConfig struct {
	Domain string `yaml:"domain"`
	Preset string `yaml:"preset,omitempty"`
}

// CompressionConfig represents compression settings
type CompressionConfig struct {
	Enable  bool `yaml:"enable"`
	Level   int  `yaml:"level,omitempty"`
	MinSize int  `yaml:"min_size,omitempty"`
}

// PresetConfig represents a custom preset for traffic generation
type PresetConfig struct {
	Name                string  `yaml:"name,omitempty"`
	Type                string  `yaml:"type,omitempty"`
	PacketSizeMin       int     `yaml:"packet_size_min,omitempty"`
	PacketSizeMax       int     `yaml:"packet_size_max,omitempty"`
	PacketsPerSecMin    int     `yaml:"packets_per_sec_min,omitempty"`
	PacketsPerSecMax    int     `yaml:"packets_per_sec_max,omitempty"`
	UploadDownloadRatio float64 `yaml:"upload_download_ratio,omitempty"`
	SessionDuration     string  `yaml:"session_duration,omitempty"`
}

// ProxyConfig represents a local proxy configuration
type ProxyConfig struct {
	Type string `yaml:"type"`
	Port int    `yaml:"port"`
}

// RoutingConfig represents routing rules configuration
type RoutingConfig struct {
	DefaultPolicy string        `yaml:"default_policy,omitempty"`
	Rules         []RoutingRule `yaml:"rules,omitempty"`
}

// RoutingRule represents a single routing rule
type RoutingRule struct {
	Type   string `yaml:"type"`
	Value  string `yaml:"value"`
	Policy string `yaml:"policy"`
}

// SettingsConfig represents general settings
type SettingsConfig struct {
	SwitchTime string `yaml:"switch_time,omitempty"`
	Randomize  bool   `yaml:"randomize,omitempty"`
}

// ConfigManager manages client configuration with hot-reload support
type ConfigManager struct {
	mu           sync.RWMutex
	config       *ClientConfig
	configPath   string
	watcher      *ConfigWatcher
	onChange     []func(*ClientConfig)
	lastModified time.Time
}

// ConfigWatcher watches for configuration file changes
type ConfigWatcher struct {
	mu       sync.Mutex
	stopCh   chan struct{}
	onChange func()
}

// NewConfigManager creates a new configuration manager
func NewConfigManager(configPath string) *ConfigManager {
	return &ConfigManager{
		configPath: configPath,
	}
}

// LoadConfig loads and validates the client configuration
func (cm *ConfigManager) LoadConfig() (*ClientConfig, error) {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	// Check if file exists
	info, err := os.Stat(cm.configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("configuration file not found: %s", cm.configPath)
		}
		return nil, fmt.Errorf("failed to access configuration file: %w", err)
	}

	// Read file
	data, err := os.ReadFile(cm.configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read configuration file: %w", err)
	}

	// Parse YAML
	var config ClientConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse YAML: %w", err)
	}

	// Validate configuration
	if err := cm.validateConfig(&config); err != nil {
		return nil, fmt.Errorf("configuration validation failed: %w", err)
	}

	// Apply defaults
	cm.applyDefaults(&config)

	cm.config = &config
	cm.lastModified = info.ModTime()

	return &config, nil
}

// GetConfig returns the current configuration
func (cm *ConfigManager) GetConfig() *ClientConfig {
	cm.mu.RLock()
	defer cm.mu.RUnlock()
	return cm.config
}

// validateConfig validates the configuration
func (cm *ConfigManager) validateConfig(config *ClientConfig) error {
	var errors []string

	// Validate required fields
	if config.Server == "" {
		errors = append(errors, "server is required")
	} else if !isValidServerAddress(config.Server) {
		errors = append(errors, "server must be in format IP:PORT or domain:PORT")
	}

	if config.UUID == "" {
		errors = append(errors, "uuid is required")
	} else if !isValidUUID(config.UUID) {
		errors = append(errors, "uuid must be a valid UUID format")
	}

	// Validate transport
	if config.Transport != "" && config.Transport != "mtp" && config.Transport != "tcp" {
		errors = append(errors, "transport must be 'mtp' or 'tcp'")
	}

	// Validate local_port
	if config.LocalPort < 0 || config.LocalPort > 65535 {
		errors = append(errors, "local_port must be between 0 and 65535")
	}

	// Validate compression
	if config.Compression != nil {
		if config.Compression.Level < 1 || config.Compression.Level > 3 {
			errors = append(errors, "compression.level must be between 1 and 3")
		}
		if config.Compression.MinSize < 0 {
			errors = append(errors, "compression.min_size must be non-negative")
		}
	}

	// Validate proxies
	for i, proxy := range config.Proxies {
		if proxy.Type != "socks5" && proxy.Type != "http" {
			errors = append(errors, fmt.Sprintf("proxies[%d].type must be 'socks5' or 'http'", i))
		}
		if proxy.Port < 1 || proxy.Port > 65535 {
			errors = append(errors, fmt.Sprintf("proxies[%d].port must be between 1 and 65535", i))
		}
	}

	// Validate routing
	if config.Routing != nil {
		if config.Routing.DefaultPolicy != "" {
			if config.Routing.DefaultPolicy != "proxy" && config.Routing.DefaultPolicy != "direct" && config.Routing.DefaultPolicy != "block" {
				errors = append(errors, "routing.default_policy must be 'proxy', 'direct', or 'block'")
			}
		}

		for i, rule := range config.Routing.Rules {
			if rule.Type != "domain_suffix" && rule.Type != "domain_keyword" && rule.Type != "ip_cidr" {
				errors = append(errors, fmt.Sprintf("routing.rules[%d].type must be 'domain_suffix', 'domain_keyword', or 'ip_cidr'", i))
			}
			if rule.Value == "" {
				errors = append(errors, fmt.Sprintf("routing.rules[%d].value is required", i))
			}
			if rule.Policy != "proxy" && rule.Policy != "direct" && rule.Policy != "block" {
				errors = append(errors, fmt.Sprintf("routing.rules[%d].policy must be 'proxy', 'direct', or 'block'", i))
			}
		}
	}

	// Validate settings
	if config.Settings != nil {
		if config.Settings.SwitchTime != "" {
			if !isValidDurationRange(config.Settings.SwitchTime) {
				errors = append(errors, "settings.switch_time must be in format '60s-300s' or '1m-5m'")
			}
		}
	}

	// Validate custom presets
	for domain, preset := range config.CustomPresets {
		if preset.Type != "" {
			validTypes := []string{"web_generic", "social", "video", "messenger", "gaming", "voip"}
			found := false
			for _, t := range validTypes {
				if preset.Type == t {
					found = true
					break
				}
			}
			if !found {
				errors = append(errors, fmt.Sprintf("custom_presets[%s].type must be one of: %s", domain, strings.Join(validTypes, ", ")))
			}
		}
		if preset.PacketSizeMin < 0 || preset.PacketSizeMax < 0 {
			errors = append(errors, fmt.Sprintf("custom_presets[%s].packet_size must be non-negative", domain))
		}
		if preset.PacketSizeMin > preset.PacketSizeMax && preset.PacketSizeMax > 0 {
			errors = append(errors, fmt.Sprintf("custom_presets[%s].packet_size_min must be <= packet_size_max", domain))
		}
	}

	if len(errors) > 0 {
		return fmt.Errorf("validation errors:\n  - %s", strings.Join(errors, "\n  - "))
	}

	return nil
}

// applyDefaults applies default values to the configuration
func (cm *ConfigManager) applyDefaults(config *ClientConfig) {
	if config.Transport == "" {
		config.Transport = "mtp"
	}

	if config.LocalPort == 0 {
		config.LocalPort = 1080
	}

	if config.DNS == "" {
		config.DNS = "1.1.1.1:53"
	}

	if config.Compression == nil {
		config.Compression = &CompressionConfig{
			Enable:  false,
			Level:   2,
			MinSize: 64,
		}
	} else {
		if config.Compression.Level == 0 {
			config.Compression.Level = 2
		}
		if config.Compression.MinSize == 0 {
			config.Compression.MinSize = 64
		}
	}

	if len(config.Proxies) == 0 {
		config.Proxies = []ProxyConfig{
			{Type: "socks5", Port: 1080},
			{Type: "http", Port: 8080},
		}
	}

	if config.Routing == nil {
		config.Routing = &RoutingConfig{
			DefaultPolicy: "proxy",
		}
	} else if config.Routing.DefaultPolicy == "" {
		config.Routing.DefaultPolicy = "proxy"
	}

	if config.Settings == nil {
		config.Settings = &SettingsConfig{
			SwitchTime: "60s-300s",
			Randomize:  true,
		}
	} else {
		if config.Settings.SwitchTime == "" {
			config.Settings.SwitchTime = "60s-300s"
		}
	}
}

// StartWatcher starts watching for configuration file changes
func (cm *ConfigManager) StartWatcher(onChange func(*ClientConfig)) error {
	cm.mu.Lock()
	cm.onChange = append(cm.onChange, onChange)
	cm.mu.Unlock()

	if cm.watcher != nil {
		return nil
	}

	cm.watcher = &ConfigWatcher{
		stopCh: make(chan struct{}),
		onChange: func() {
			config, err := cm.LoadConfig()
			if err != nil {
				fmt.Printf("Error reloading config: %v\n", err)
				return
			}

			cm.mu.RLock()
			callbacks := cm.onChange
			cm.mu.RUnlock()

			for _, cb := range callbacks {
				cb(config)
			}
		},
	}

	go cm.watchLoop()
	return nil
}

// StopWatcher stops the configuration file watcher
func (cm *ConfigManager) StopWatcher() {
	if cm.watcher != nil {
		close(cm.watcher.stopCh)
		cm.watcher = nil
	}
}

// watchLoop monitors the configuration file for changes
func (cm *ConfigManager) watchLoop() {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-cm.watcher.stopCh:
			return
		case <-ticker.C:
			cm.checkForChanges()
		}
	}
}

// checkForChanges checks if the configuration file has been modified
func (cm *ConfigManager) checkForChanges() {
	info, err := os.Stat(cm.configPath)
	if err != nil {
		return
	}

	cm.mu.RLock()
	lastModified := cm.lastModified
	cm.mu.RUnlock()

	if info.ModTime().After(lastModified) {
		cm.watcher.onChange()
	}
}

// ReloadConfig forces a configuration reload
func (cm *ConfigManager) ReloadConfig() (*ClientConfig, error) {
	return cm.LoadConfig()
}

// Helper functions

func isValidServerAddress(addr string) bool {
	// Check for IP:PORT or domain:PORT format
	parts := strings.Split(addr, ":")
	if len(parts) != 2 {
		return false
	}

	host := parts[0]
	port := parts[1]

	// Validate port
	if port == "" {
		return false
	}

	// Check if host is valid (IP or domain)
	if net.ParseIP(host) != nil {
		return true
	}

	// Check if it's a valid domain
	if strings.Contains(host, ".") && !strings.Contains(host, " ") {
		return true
	}

	return false
}

func isValidUUID(uuid string) bool {
	// Simple UUID validation (8-4-4-4-12 format)
	parts := strings.Split(uuid, "-")
	if len(parts) != 5 {
		return false
	}

	lengths := []int{8, 4, 4, 4, 12}
	for i, part := range parts {
		if len(part) != lengths[i] {
			return false
		}
		for _, c := range part {
			if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
				return false
			}
		}
	}

	return true
}

func isValidDurationRange(s string) bool {
	// Check format like "60s-300s" or "1m-5m"
	parts := strings.Split(s, "-")
	if len(parts) != 2 {
		return false
	}

	_, err1 := time.ParseDuration(parts[0])
	_, err2 := time.ParseDuration(parts[1])

	return err1 == nil && err2 == nil
}

// GetDefaultConfigPath returns the default configuration file path
func GetDefaultConfigPath() string {
	// Check environment variable first
	if path := os.Getenv("MIMIC_CONFIG"); path != "" {
		return path
	}

	// Check common locations
	homeDir, err := os.UserHomeDir()
	if err == nil {
		configPath := filepath.Join(homeDir, ".config", "mimic", "client.yaml")
		if _, err := os.Stat(configPath); err == nil {
			return configPath
		}
	}

	// Check current directory
	if _, err := os.Stat("client.yaml"); err == nil {
		return "client.yaml"
	}

	return ""
}

// CreateDefaultConfig creates a default configuration file
func CreateDefaultConfig(path string) error {
	config := ClientConfig{
		Server: "your-mimic-server.com:443",
		UUID:   "550e8400-e29b-41d4-a716-446655440000",
		Domains: []DomainConfig{
			{Domain: "vk.com"},
			{Domain: "rutube.ru"},
			{Domain: "telegram.org"},
		},
		Transport: "mtp",
		LocalPort: 1080,
		DNS:       "1.1.1.1:53",
		Compression: &CompressionConfig{
			Enable:  false,
			Level:   2,
			MinSize: 64,
		},
		CustomPresets: map[string]PresetConfig{
			"discord.com": {
				Name:                "VoIP - Discord",
				Type:                "voip",
				PacketSizeMin:       80,
				PacketSizeMax:       300,
				PacketsPerSecMin:    20,
				PacketsPerSecMax:    50,
				UploadDownloadRatio: 1.0,
				SessionDuration:     "300s-7200s",
			},
		},
		Proxies: []ProxyConfig{
			{Type: "socks5", Port: 1080},
			{Type: "http", Port: 8080},
		},
		Routing: &RoutingConfig{
			DefaultPolicy: "proxy",
			Rules: []RoutingRule{
				{Type: "domain_suffix", Value: "ru", Policy: "direct"},
				{Type: "ip_cidr", Value: "127.0.0.0/8", Policy: "block"},
			},
		},
		Settings: &SettingsConfig{
			SwitchTime: "60s-300s",
			Randomize:  true,
		},
	}

	data, err := yaml.Marshal(&config)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	// Create directory if it doesn't exist
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	return nil
}
