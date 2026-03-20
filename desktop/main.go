// Package main provides a CGO interface for Mimic Protocol.
// This package is designed to be compiled as a shared library for Windows, Linux, and macOS.
package main

/*
#include <stdint.h>
#include <stdlib.h>

// NetworkStats structure for C.
// The explicit tag is required for cgo-exported functions on macOS,
// where generated wrappers refer to `struct NetworkStats`.
typedef struct NetworkStats {
    int64_t download_speed;
    int64_t upload_speed;
    int64_t ping;
    int64_t total_download;
    int64_t total_upload;
    int64_t last_updated;
} NetworkStats;
*/
import "C"

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

	"github.com/Locon213/Mimic-App/service"
	"github.com/Locon213/Mimic-Protocol/pkg/client"
	"github.com/Locon213/Mimic-Protocol/pkg/config"
)

// ConnectionStatus represents the current connection state
type ConnectionStatus int32

const (
	StatusDisconnected ConnectionStatus = iota
	StatusConnecting
	StatusConnected
	StatusReconnecting
)

// NetworkStats holds network statistics
type NetworkStats struct {
	DownloadSpeed int64 // bytes per second
	UploadSpeed   int64 // bytes per second
	Ping          int64 // milliseconds
	TotalDownload int64 // total bytes received
	TotalUpload   int64 // total bytes sent
	LastUpdated   int64 // unix timestamp
}

// clientHolder holds the client state
type clientHolder struct {
	client     *client.Client
	ctx        context.Context
	cancel     context.CancelFunc
	serverName string
	serverURL  string
	mode       string
	status     atomic.Int32
	lastStats  NetworkStats
	mu         sync.RWMutex
}

// Global client storage
var (
	globalHolder *clientHolder
	holderMu     sync.Mutex
	logBuffer    = newNativeLogBuffer(400)
)

type nativeLogEntry struct {
	Level     string `json:"level"`
	Source    string `json:"source"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

type nativeLogBuffer struct {
	mu      sync.Mutex
	entries []string
	maxSize int
}

func newNativeLogBuffer(maxSize int) *nativeLogBuffer {
	return &nativeLogBuffer{maxSize: maxSize}
}

func (b *nativeLogBuffer) push(entry nativeLogEntry) {
	b.mu.Lock()
	defer b.mu.Unlock()

	payload, err := json.Marshal(entry)
	if err != nil {
		return
	}

	b.entries = append(b.entries, string(payload))
	if len(b.entries) > b.maxSize {
		b.entries = b.entries[len(b.entries)-b.maxSize:]
	}
}

func (b *nativeLogBuffer) pop() string {
	b.mu.Lock()
	defer b.mu.Unlock()

	if len(b.entries) == 0 {
		return ""
	}

	entry := b.entries[0]
	b.entries = b.entries[1:]
	return entry
}

type logCaptureWriter struct{}

func (w *logCaptureWriter) Write(p []byte) (int, error) {
	text := strings.TrimSpace(string(p))
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		pushNativeLog("info", "GoBackend", line)
	}
	return len(p), nil
}

func pushNativeLog(level, source, message string) {
	logBuffer.push(nativeLogEntry{
		Level:     level,
		Source:    source,
		Message:   message,
		Timestamp: time.Now().UnixMilli(),
	})
}

func init() {
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)
	log.SetOutput(io.MultiWriter(&logCaptureWriter{}))
	pushNativeLog("info", "GoBackend", "Desktop CGO backend initialized.")
}

//export MimicClient_Connect
func MimicClient_Connect(serverURL, mode *C.char) *C.char {
	cURL := C.GoString(serverURL)
	cMode := C.GoString(mode)

	cfg, err := config.ParseMimicURL(cURL)
	if err != nil {
		return C.CString(fmt.Sprintf("failed to parse URL: %v", err))
	}

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
		return C.CString(fmt.Sprintf("failed to create client: %v", err))
	}

	ctx, cancel := context.WithCancel(context.Background())

	mimicClient.SetTrafficCallback(func(stats client.NetworkStats) {
		if globalHolder != nil {
			globalHolder.mu.Lock()
			globalHolder.lastStats = NetworkStats{
				DownloadSpeed: stats.DownloadSpeed,
				UploadSpeed:   stats.UploadSpeed,
				Ping:          stats.Ping,
				TotalDownload: stats.TotalDownload,
				TotalUpload:   stats.TotalUpload,
				LastUpdated:   time.Now().Unix(),
			}
			globalHolder.mu.Unlock()
		}
	})

	if err := mimicClient.Start(ctx); err != nil {
		cancel()
		pushNativeLog("error", "GoBackend", fmt.Sprintf("failed to start client: %v", err))
		return C.CString(fmt.Sprintf("failed to start client: %v", err))
	}

	if err := mimicClient.StartProxies(); err != nil {
		mimicClient.Stop()
		cancel()
		pushNativeLog("error", "GoBackend", fmt.Sprintf("failed to start proxies: %v", err))
		return C.CString(fmt.Sprintf("failed to start proxies: %v", err))
	}

	holderMu.Lock()
	globalHolder = &clientHolder{
		client:     mimicClient,
		ctx:        ctx,
		cancel:     cancel,
		serverURL:  cURL,
		mode:       cMode,
		serverName: extractServerName(cURL),
	}
	globalHolder.status.Store(int32(StatusConnected))
	holderMu.Unlock()
	pushNativeLog("info", "GoBackend", fmt.Sprintf("connected to %s in %s mode", globalHolder.serverName, cMode))

	// Start TUN mode if requested (for Desktop)
	if strings.Contains(cMode, "TUN") {
		service.ConfigureTunRemoteAddress(cfg.Server)
		go func() {
			if err := service.StartTun2Socks(); err != nil {
				pushNativeLog("error", "GoBackend", fmt.Sprintf("failed to start TUN: %v", err))
				fmt.Printf("Failed to start TUN: %v\n", err)
			}
		}()
	}

	// Set system proxy for Proxy mode on Desktop
	if strings.Contains(cMode, "Proxy") {
		setSystemProxy(true)
	}

	return C.CString("") // Empty string means success
}

//export MimicClient_Disconnect
func MimicClient_Disconnect() {
	pushNativeLog("info", "GoBackend", "disconnect requested")
	// Reset system proxy
	setSystemProxy(false)

	// Stop TUN
	service.StopTun2Socks()

	holderMu.Lock()
	defer holderMu.Unlock()

	if globalHolder != nil {
		if globalHolder.cancel != nil {
			globalHolder.cancel()
		}
		if globalHolder.client != nil {
			globalHolder.client.Stop()
		}
		globalHolder = nil
	}
}

//export MimicClient_IsConnected
func MimicClient_IsConnected() C.int {
	holderMu.Lock()
	defer holderMu.Unlock()

	if globalHolder == nil {
		return 0
	}
	if globalHolder.status.Load() == int32(StatusConnected) {
		return 1
	}
	return 0
}

//export MimicClient_GetStatus
func MimicClient_GetStatus() C.int {
	holderMu.Lock()
	defer holderMu.Unlock()

	if globalHolder == nil {
		return C.int(StatusDisconnected)
	}
	return C.int(globalHolder.status.Load())
}

//export MimicClient_GetStats
func MimicClient_GetStats() C.NetworkStats {
	holderMu.Lock()
	defer holderMu.Unlock()

	if globalHolder == nil {
		return C.NetworkStats{}
	}

	return C.NetworkStats{
		download_speed: C.int64_t(globalHolder.lastStats.DownloadSpeed),
		upload_speed:   C.int64_t(globalHolder.lastStats.UploadSpeed),
		ping:           C.int64_t(globalHolder.lastStats.Ping),
		total_download: C.int64_t(globalHolder.lastStats.TotalDownload),
		total_upload:   C.int64_t(globalHolder.lastStats.TotalUpload),
		last_updated:   C.int64_t(globalHolder.lastStats.LastUpdated),
	}
}

//export MimicClient_GetStatsLegacy
func MimicClient_GetStatsLegacy() C.NetworkStats {
	holderMu.Lock()
	defer holderMu.Unlock()

	if globalHolder == nil {
		return C.NetworkStats{}
	}

	return C.NetworkStats{
		download_speed: C.int64_t(globalHolder.lastStats.DownloadSpeed),
		upload_speed:   C.int64_t(globalHolder.lastStats.UploadSpeed),
		ping:           C.int64_t(globalHolder.lastStats.Ping),
		total_download: C.int64_t(globalHolder.lastStats.TotalDownload),
		total_upload:   C.int64_t(globalHolder.lastStats.TotalUpload),
		last_updated:   C.int64_t(globalHolder.lastStats.LastUpdated),
	}
}

//export MimicClient_GetServerName
func MimicClient_GetServerName() *C.char {
	holderMu.Lock()
	defer holderMu.Unlock()

	if globalHolder == nil {
		return C.CString("")
	}
	return C.CString(globalHolder.serverName)
}

//export MimicClient_FreeString
func MimicClient_FreeString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

//export MimicClient_PollLog
func MimicClient_PollLog() *C.char {
	return C.CString(logBuffer.pop())
}

//export MimicClient_FormatBytes
func MimicClient_FormatBytes(bytes C.int64_t) *C.char {
	b := int64(bytes)
	const unit = 1024
	if b < unit {
		return C.CString(fmt.Sprintf("%d B", b))
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return C.CString(fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp]))
}

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

// setSystemProxy sets or resets the system HTTP/SOCKS5 proxy
func setSystemProxy(enable bool) {
	if runtime.GOOS == "windows" {
		setWindowsProxy(enable)
	} else if runtime.GOOS == "darwin" {
		setMacOSProxy(enable)
	} else if runtime.GOOS == "linux" {
		setLinuxProxy(enable)
	}
}

// setWindowsProxy configures proxy on Windows
func setWindowsProxy(enable bool) {
	const internetSettings = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings"
	const proxyServer = "http=127.0.0.1:1081;https=127.0.0.1:1081;socks=127.0.0.1:1080"

	if enable {
		// Configure per-protocol proxies so Windows surfaces the expected
		// HTTP/HTTPS/SOCKS entries in the system proxy UI.
		runCommand("reg", "add", internetSettings,
			"/v", "ProxyEnable", "/t", "REG_DWORD", "/d", "1", "/f")
		runCommand("reg", "add", internetSettings,
			"/v", "ProxyServer", "/t", "REG_SZ", "/d", proxyServer, "/f")
		runCommand("reg", "add", internetSettings,
			"/v", "ProxyOverride", "/t", "REG_SZ", "/d", "<local>", "/f")
		runCommand("reg", "delete", internetSettings,
			"/v", "AutoConfigURL", "/f")
		runCommand("reg", "add", internetSettings,
			"/v", "AutoDetect", "/t", "REG_DWORD", "/d", "0", "/f")

		// Wait for registry to update
		time.Sleep(500 * time.Millisecond)

		// Refresh Internet settings for WinINet-based applications.
		runCommand("RUNDLL32.EXE", "wininet.dll,InternetSetOption", "0", "39", "0")
		runCommand("RUNDLL32.EXE", "wininet.dll,InternetSetOption", "0", "37", "0")

		// Best-effort sync for WinHTTP consumers on Windows.
		runCommand("netsh", "winhttp", "set", "proxy", proxyServer, "bypass-list=<local>")
	} else {
		// Disable proxy
		runCommand("reg", "add", internetSettings,
			"/v", "ProxyEnable", "/t", "REG_DWORD", "/d", "0", "/f")
		runCommand("netsh", "winhttp", "reset", "proxy")

		// Wait for registry to update
		time.Sleep(500 * time.Millisecond)

		// Refresh Internet settings
		runCommand("RUNDLL32.EXE", "wininet.dll,InternetSetOption", "0", "39", "0")
		runCommand("RUNDLL32.EXE", "wininet.dll,InternetSetOption", "0", "37", "0")
	}
}

// setMacOSProxy configures proxy on macOS
func setMacOSProxy(enable bool) {
	services := listMacOSNetworkServices()
	if len(services) == 0 {
		log.Println("no macOS network services detected for proxy configuration")
		return
	}

	for _, service := range services {
		if enable {
			runCommand("networksetup", "-setwebproxy", service, "127.0.0.1", "1081")
			runCommand("networksetup", "-setsecurewebproxy", service, "127.0.0.1", "1081")
			runCommand("networksetup", "-setsocksfirewallproxy", service, "127.0.0.1", "1080")
			runCommand("networksetup", "-setproxybypassdomains", service, "localhost", "127.0.0.1", "::1")
			runCommand("networksetup", "-setwebproxystate", service, "on")
			runCommand("networksetup", "-setsecurewebproxystate", service, "on")
			runCommand("networksetup", "-setsocksfirewallproxystate", service, "on")
			continue
		}

		runCommand("networksetup", "-setwebproxystate", service, "off")
		runCommand("networksetup", "-setsecurewebproxystate", service, "off")
		runCommand("networksetup", "-setsocksfirewallproxystate", service, "off")
	}
}

// setLinuxProxy configures proxy on Linux
func setLinuxProxy(enable bool) {
	if enable {
		_ = os.Setenv("HTTP_PROXY", "http://127.0.0.1:1081")
		_ = os.Setenv("HTTPS_PROXY", "http://127.0.0.1:1081")
		_ = os.Setenv("ALL_PROXY", "socks5://127.0.0.1:1080")
		_ = os.Setenv("http_proxy", "http://127.0.0.1:1081")
		_ = os.Setenv("https_proxy", "http://127.0.0.1:1081")
		_ = os.Setenv("all_proxy", "socks5://127.0.0.1:1080")
		_ = os.Setenv("NO_PROXY", "localhost,127.0.0.1,::1")
		_ = os.Setenv("no_proxy", "localhost,127.0.0.1,::1")
	} else {
		for _, key := range []string{"HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy", "NO_PROXY", "no_proxy"} {
			_ = os.Unsetenv(key)
		}
	}

	if commandExists("gsettings") {
		// Configure GNOME-compatible desktop environments when available.
		if enable {
			runCommand("gsettings", "set", "org.gnome.system.proxy", "mode", "manual")
			runCommand("gsettings", "set", "org.gnome.system.proxy.http", "host", "127.0.0.1")
			runCommand("gsettings", "set", "org.gnome.system.proxy.http", "port", "1081")
			runCommand("gsettings", "set", "org.gnome.system.proxy.https", "host", "127.0.0.1")
			runCommand("gsettings", "set", "org.gnome.system.proxy.https", "port", "1081")
			runCommand("gsettings", "set", "org.gnome.system.proxy.socks", "host", "127.0.0.1")
			runCommand("gsettings", "set", "org.gnome.system.proxy.socks", "port", "1080")
			runCommand("gsettings", "set", "org.gnome.system.proxy", "ignore-hosts", "['localhost', '127.0.0.1', '::1']")
		} else {
			runCommand("gsettings", "set", "org.gnome.system.proxy", "mode", "none")
		}
	} else {
		log.Println("gsettings is not available; skipping GNOME proxy configuration")
	}

	setKDEProxy(enable)
}

func listMacOSNetworkServices() []string {
	if !commandExists("networksetup") {
		return nil
	}

	output, err := runCommandOutput("networksetup", "-listallnetworkservices")
	if err != nil {
		return nil
	}

	var services []string
	for _, line := range strings.Split(output, "\n") {
		service := strings.TrimSpace(line)
		if service == "" || strings.HasPrefix(service, "An asterisk") || strings.HasPrefix(service, "*") {
			continue
		}
		services = append(services, service)
	}

	return services
}

func setKDEProxy(enable bool) {
	bin := firstAvailableCommand("kwriteconfig6", "kwriteconfig5")
	if bin == "" {
		return
	}

	if enable {
		runCommand(bin, "--file", "kioslaverc", "--group", "Proxy Settings", "--key", "ProxyType", "1")
		runCommand(bin, "--file", "kioslaverc", "--group", "Proxy Settings", "--key", "httpProxy", "http://127.0.0.1 1081")
		runCommand(bin, "--file", "kioslaverc", "--group", "Proxy Settings", "--key", "httpsProxy", "http://127.0.0.1 1081")
		runCommand(bin, "--file", "kioslaverc", "--group", "Proxy Settings", "--key", "socksProxy", "socks://127.0.0.1 1080")
		runCommand(bin, "--file", "kioslaverc", "--group", "Proxy Settings", "--key", "NoProxyFor", "localhost,127.0.0.1,::1")
	} else {
		runCommand(bin, "--file", "kioslaverc", "--group", "Proxy Settings", "--key", "ProxyType", "0")
	}

	notifyKDEProxyReload()
}

func notifyKDEProxyReload() {
	if commandExists("qdbus6") {
		runCommand("qdbus6", "org.kde.KIO.Scheduler", "/KIO/Scheduler", "org.kde.KIO.Scheduler.reparseSlaveConfiguration", "")
		return
	}
	if commandExists("qdbus") {
		runCommand("qdbus", "org.kde.KIO.Scheduler", "/KIO/Scheduler", "org.kde.KIO.Scheduler.reparseSlaveConfiguration", "")
		return
	}
	if commandExists("dbus-send") {
		runCommand("dbus-send", "--session", "--dest=org.kde.KIO.Scheduler", "/KIO/Scheduler", "org.kde.KIO.Scheduler.reparseSlaveConfiguration", "string:")
	}
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func firstAvailableCommand(names ...string) string {
	for _, name := range names {
		if commandExists(name) {
			return name
		}
	}
	return ""
}

func runCommandOutput(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("command failed: %s %s: %v (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(output)))
		return "", err
	}
	return string(output), nil
}

// runCommand runs a helper command and logs failures instead of silently hiding them.
func runCommand(name string, args ...string) {
	// #nosec G204 - Command execution is intentional
	cmd := exec.Command(name, args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("command failed: %s %s: %v (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(output)))
	}
}

func main() {}
