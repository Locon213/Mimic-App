// Package main provides a CGO interface for Mimic Protocol.
// This package is designed to be compiled as a shared library for Windows, Linux, and macOS.
package main

/*
#include <stdint.h>
#include <stdlib.h>

// NetworkStats structure for C
typedef struct {
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
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

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
)

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
		return C.CString(fmt.Sprintf("failed to start client: %v", err))
	}

	if err := mimicClient.StartProxies(); err != nil {
		mimicClient.Stop()
		cancel()
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

	return C.CString("") // Empty string means success
}

//export MimicClient_Disconnect
func MimicClient_Disconnect() {
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

func main() {}
