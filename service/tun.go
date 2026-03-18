package service

import (
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"runtime"
	"sync/atomic"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/engine"
)

var tunRunning atomic.Bool

// StartTun2Socks starts tun2socks tunneling to the local Mimic SOCKS5 proxy.
func StartTun2Socks() error {
	if tunRunning.Load() {
		log.Println("TUN is already running")
		return nil
	}

	log.Println("TUN mode requested. Starting tun2socks engine...")

	// Platform-specific TUN setup
	if runtime.GOOS == "windows" {
		if err := setupWindowsTun(); err != nil {
			return fmt.Errorf("failed to setup Windows TUN: %w", err)
		}
	}

	key := &engine.Key{
		Proxy:    "socks5://127.0.0.1:1080",
		Device:   getTunDeviceName(),
		LogLevel: "info",
	}

	os.Setenv("TUN2SOCKS_LOGLEVEL", "info")

	// Recover from potential panic
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Panic in StartTun2Socks: %v\n", r)
			tunRunning.Store(false)
		}
	}()

	go func() {
		// v2 engine.Start() accepts no arguments.
		// The key must be passed to Insert first.
		engine.Insert(key)
		engine.Start()
		tunRunning.Store(true)
	}()

	// Wait for TUN to start
	time.Sleep(2 * time.Second)

	// Setup routing after TUN starts
	if runtime.GOOS == "windows" {
		if err := setupWindowsRoutes(); err != nil {
			log.Printf("Warning: failed to setup Windows routes: %v", err)
		}
	}

	return nil
}

// getTunDeviceName returns platform-specific TUN device name
func getTunDeviceName() string {
	switch runtime.GOOS {
	case "windows":
		return "MimicTUN" // Wintun adapter name
	case "darwin":
		return "utun0"
	case "linux":
		return "tun0"
	default:
		return "tun0"
	}
}

// setupWindowsTun sets up Windows TUN adapter
func setupWindowsTun() error {
	log.Println("Setting up Windows TUN adapter...")

	// Check if running as administrator
	if !isRunningAsAdmin() {
		log.Println("Warning: Not running as administrator. TUN mode may not work.")
	}

	// Install Wintun driver if needed
	wintunDll := findWintunDll()
	if wintunDll != "" {
		log.Printf("Found Wintun DLL: %s", wintunDll)
		os.Setenv("WINTUN_DLL", wintunDll)
	}

	return nil
}

// setupWindowsRoutes sets up routing table for Windows TUN
func setupWindowsRoutes() error {
	log.Println("Setting up Windows TUN routes...")

	// Get TUN interface index
	tunIndex := getTunInterfaceIndex()
	if tunIndex == -1 {
		return fmt.Errorf("TUN interface not found")
	}

	// Add default route through TUN (0.0.0.0/0)
	// This routes all traffic through the VPN
	cmd := exec.Command("netsh", "interface", "ipv4", "add", "route",
		"0.0.0.0/0", fmt.Sprintf("%d", tunIndex),
		"10.0.0.1", "metric=1")
	if err := cmd.Run(); err != nil {
		log.Printf("Warning: failed to add default route: %v", err)
	}

	// Add IPv6 default route
	cmd = exec.Command("netsh", "interface", "ipv6", "add", "route",
		"::/0", fmt.Sprintf("%d", tunIndex),
		"fd00::1", "metric=1")
	if err := cmd.Run(); err != nil {
		log.Printf("Warning: failed to add IPv6 default route: %v", err)
	}

	log.Println("Windows TUN routes configured")
	return nil
}

// getTunInterfaceIndex returns the interface index of TUN adapter
func getTunInterfaceIndex() int {
	interfaces, err := net.Interfaces()
	if err != nil {
		return -1
	}

	for _, iface := range interfaces {
		// Look for TUN interface by name
		if iface.Name == "MimicTUN" || iface.Name == "utun0" || iface.Name == "tun0" {
			return iface.Index
		}
	}

	return -1
}

// isRunningAsAdmin checks if the process is running as administrator on Windows
func isRunningAsAdmin() bool {
	if runtime.GOOS != "windows" {
		return true // Unix systems handle permissions differently
	}

	cmd := exec.Command("net", "session")
	return cmd.Run() == nil
}

// findWintunDll searches for Wintun DLL in common locations
func findWintunDll() string {
	// Check current directory first
	if _, err := os.Stat("wintun.dll"); err == nil {
		pwd, _ := os.Getwd()
		return pwd + "\\wintun.dll"
	}

	// Check program files
	paths := []string{
		"C:\\Program Files\\Mimic\\wintun.dll",
		"C:\\Program Files (x86)\\Mimic\\wintun.dll",
	}

	for _, path := range paths {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	return ""
}

func StopTun2Socks() {
	if !tunRunning.Load() {
		return
	}

	log.Println("Stopping tun2socks engine...")

	// Clean up routes on Windows
	if runtime.GOOS == "windows" {
		cleanupWindowsRoutes()
	}

	// Recover from potential panic
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Panic in StopTun2Socks: %v\n", r)
		}
	}()

	engine.Stop()
	tunRunning.Store(false)
}

// cleanupWindowsRoutes removes TUN routes from Windows routing table
func cleanupWindowsRoutes() {
	log.Println("Cleaning up Windows TUN routes...")

	tunIndex := getTunInterfaceIndex()
	if tunIndex == -1 {
		return
	}

	// Remove default route
	cmd := exec.Command("netsh", "interface", "ipv4", "delete", "route",
		"0.0.0.0/0", fmt.Sprintf("%d", tunIndex))
	_ = cmd.Run()

	// Remove IPv6 default route
	cmd = exec.Command("netsh", "interface", "ipv6", "delete", "route",
		"::/0", fmt.Sprintf("%d", tunIndex))
	_ = cmd.Run()

	log.Println("Windows TUN routes cleaned up")
}

// IsTunRunning returns true if TUN is currently running
func IsTunRunning() bool {
	return tunRunning.Load()
}
