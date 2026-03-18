package service

import (
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync/atomic"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/engine"
)

var tunRunning atomic.Bool

const (
	windowsTunName      = "MimicTUN"
	windowsTunIPv4Addr  = "10.0.0.2"
	windowsTunIPv4Mask  = "255.255.255.0"
	windowsTunIPv4GW    = "10.0.0.1"
	windowsTunIPv6CIDR  = "fd00::2/64"
	windowsTunIPv6GW    = "fd00::1"
	windowsTunDNS       = "1.1.1.1"
	windowsTunRouteDest = "0.0.0.0"
	tunIPv4CIDR         = "10.0.0.2/24"
	tunIPv4Peer         = "10.0.0.1"
)

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
		Device:   fmt.Sprintf("tun://%s", getTunDeviceName()),
		LogLevel: "info",
		MTU:      1500,
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
	tunRunning.Store(true)

	// Setup routing after TUN starts
	var routeErr error
	switch runtime.GOOS {
	case "windows":
		routeErr = setupWindowsRoutes()
	case "linux":
		routeErr = setupLinuxTun()
	case "darwin":
		routeErr = setupMacOSTun()
	}
	if routeErr != nil {
		tunRunning.Store(false)
		engine.Stop()
		log.Printf("Warning: failed to setup TUN routes: %v", routeErr)
		return routeErr
	}

	return nil
}

// getTunDeviceName returns platform-specific TUN device name
func getTunDeviceName() string {
	switch runtime.GOOS {
	case "windows":
		return windowsTunName // Wintun adapter name
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
		return errors.New("TUN mode on Windows requires Administrator rights")
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

	iface, err := waitForTunInterface(10 * time.Second)
	if err != nil {
		return err
	}

	if err := configureWindowsTunInterface(iface); err != nil {
		return err
	}

	if err := setWindowsTunMetrics(iface.Name); err != nil {
		log.Printf("Warning: failed to adjust TUN metrics: %v", err)
	}

	if err := addWindowsTunRoutes(iface); err != nil {
		return err
	}

	log.Printf("Windows TUN routes configured on %s (index=%d)", iface.Name, iface.Index)
	return nil
}

func waitForTunInterface(timeout time.Duration) (*net.Interface, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		iface, err := getTunInterface()
		if err == nil {
			return iface, nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return nil, fmt.Errorf("TUN interface not found on %s", runtime.GOOS)
}

func configureWindowsTunInterface(iface *net.Interface) error {
	log.Printf("Configuring Windows TUN adapter %s...", iface.Name)

	if err := runWindowsCommand("netsh", "interface", "ipv4", "set", "address",
		fmt.Sprintf("name=%s", iface.Name), "static", windowsTunIPv4Addr, windowsTunIPv4Mask, windowsTunIPv4GW); err != nil {
		return fmt.Errorf("set IPv4 address: %w", err)
	}

	if err := runWindowsCommand("netsh", "interface", "ipv4", "set", "dnsservers",
		fmt.Sprintf("name=%s", iface.Name), "static", windowsTunDNS, "primary", "validate=no"); err != nil {
		log.Printf("Warning: failed to set TUN DNS server: %v", err)
	}

	if err := runWindowsCommand("netsh", "interface", "ipv6", "set", "address",
		fmt.Sprintf("interface=%s", iface.Name), fmt.Sprintf("address=%s", windowsTunIPv6CIDR)); err != nil {
		log.Printf("Warning: failed to set IPv6 address on TUN: %v", err)
	}

	return nil
}

func setWindowsTunMetrics(name string) error {
	if err := runWindowsCommand("netsh", "interface", "ipv4", "set", "interface",
		fmt.Sprintf("interface=%s", name), "metric=1"); err != nil {
		return err
	}

	if err := runWindowsCommand("netsh", "interface", "ipv6", "set", "interface",
		fmt.Sprintf("interface=%s", name), "metric=1"); err != nil {
		log.Printf("Warning: failed to set IPv6 metric: %v", err)
	}

	return nil
}

func addWindowsTunRoutes(iface *net.Interface) error {
	if err := runWindowsCommand("route", "add", windowsTunRouteDest, "mask", windowsTunRouteDest,
		windowsTunIPv4GW, "if", fmt.Sprintf("%d", iface.Index), "metric", "1"); err != nil {
		return fmt.Errorf("add IPv4 default route: %w", err)
	}

	if err := runWindowsCommand("netsh", "interface", "ipv6", "add", "route", "::/0",
		fmt.Sprintf("interface=%s", iface.Name), windowsTunIPv6GW, "metric=1", "store=active"); err != nil {
		log.Printf("Warning: failed to add IPv6 default route: %v", err)
	}

	return nil
}

func getTunInterface() (*net.Interface, error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}

	for _, iface := range interfaces {
		if isTunInterfaceName(iface.Name) {
			copied := iface
			return &copied, nil
		}
	}

	return nil, fmt.Errorf("TUN interface not found")
}

// getTunInterfaceIndex returns the interface index of TUN adapter
func getTunInterfaceIndex() int {
	iface, err := getTunInterface()
	if err != nil {
		return -1
	}
	return iface.Index
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

	// Clean up platform-specific routes before closing the engine.
	switch runtime.GOOS {
	case "windows":
		cleanupWindowsRoutes()
	case "linux":
		cleanupLinuxTun()
	case "darwin":
		cleanupMacOSTun()
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

	iface, err := getTunInterface()
	if err != nil {
		return
	}

	_ = runWindowsCommand("route", "delete", windowsTunRouteDest, "mask", windowsTunRouteDest,
		windowsTunIPv4GW, "if", fmt.Sprintf("%d", iface.Index))

	_ = runWindowsCommand("netsh", "interface", "ipv6", "delete", "route", "::/0",
		fmt.Sprintf("interface=%s", iface.Name), windowsTunIPv6GW)

	log.Println("Windows TUN routes cleaned up")
}

func setupLinuxTun() error {
	iface, err := waitForTunInterface(10 * time.Second)
	if err != nil {
		return err
	}

	if err := runSystemCommand("ip", "link", "set", "dev", iface.Name, "up", "mtu", "1500"); err != nil {
		return fmt.Errorf("bring Linux TUN up: %w", err)
	}
	if err := runSystemCommand("ip", "addr", "replace", tunIPv4CIDR, "dev", iface.Name); err != nil {
		return fmt.Errorf("assign Linux TUN IPv4: %w", err)
	}
	if err := runSystemCommand("ip", "-6", "addr", "replace", windowsTunIPv6CIDR, "dev", iface.Name); err != nil {
		log.Printf("Warning: failed to assign Linux TUN IPv6: %v", err)
	}
	if err := runSystemCommand("ip", "route", "replace", "0.0.0.0/1", "dev", iface.Name, "metric", "1"); err != nil {
		return fmt.Errorf("add Linux split route 0.0.0.0/1: %w", err)
	}
	if err := runSystemCommand("ip", "route", "replace", "128.0.0.0/1", "dev", iface.Name, "metric", "1"); err != nil {
		return fmt.Errorf("add Linux split route 128.0.0.0/1: %w", err)
	}
	if err := runSystemCommand("ip", "-6", "route", "replace", "::/1", "dev", iface.Name, "metric", "1"); err != nil {
		log.Printf("Warning: failed to add Linux IPv6 split route ::/1: %v", err)
	}
	if err := runSystemCommand("ip", "-6", "route", "replace", "8000::/1", "dev", iface.Name, "metric", "1"); err != nil {
		log.Printf("Warning: failed to add Linux IPv6 split route 8000::/1: %v", err)
	}

	log.Printf("Linux TUN configured on %s", iface.Name)
	return nil
}

func setupMacOSTun() error {
	iface, err := waitForTunInterface(10 * time.Second)
	if err != nil {
		return err
	}

	if err := runSystemCommand("ifconfig", iface.Name, "inet", windowsTunIPv4Addr, tunIPv4Peer, "up"); err != nil {
		return fmt.Errorf("assign macOS TUN IPv4: %w", err)
	}
	if err := runSystemCommand("ifconfig", iface.Name, "mtu", "1500"); err != nil {
		log.Printf("Warning: failed to set macOS TUN MTU: %v", err)
	}
	if err := runSystemCommand("route", "-n", "add", "-inet", "0.0.0.0/1", tunIPv4Peer); err != nil {
		return fmt.Errorf("add macOS split route 0.0.0.0/1: %w", err)
	}
	if err := runSystemCommand("route", "-n", "add", "-inet", "128.0.0.0/1", tunIPv4Peer); err != nil {
		return fmt.Errorf("add macOS split route 128.0.0.0/1: %w", err)
	}

	log.Printf("macOS TUN configured on %s", iface.Name)
	return nil
}

func cleanupLinuxTun() {
	iface, err := getTunInterface()
	if err != nil {
		return
	}

	_ = runSystemCommand("ip", "route", "del", "0.0.0.0/1", "dev", iface.Name)
	_ = runSystemCommand("ip", "route", "del", "128.0.0.0/1", "dev", iface.Name)
	_ = runSystemCommand("ip", "-6", "route", "del", "::/1", "dev", iface.Name)
	_ = runSystemCommand("ip", "-6", "route", "del", "8000::/1", "dev", iface.Name)
}

func cleanupMacOSTun() {
	_ = runSystemCommand("route", "-n", "delete", "-inet", "0.0.0.0/1")
	_ = runSystemCommand("route", "-n", "delete", "-inet", "128.0.0.0/1")
}

func isTunInterfaceName(name string) bool {
	lowerName := strings.ToLower(name)
	return lowerName == strings.ToLower(windowsTunName) ||
		strings.Contains(lowerName, "mimictun") ||
		strings.HasPrefix(lowerName, "utun") ||
		strings.HasPrefix(lowerName, "tun")
}

func runWindowsCommand(name string, args ...string) error {
	return runSystemCommand(name, args...)
}

func runSystemCommand(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s failed: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(output)))
	}
	if trimmed := strings.TrimSpace(string(output)); trimmed != "" {
		log.Printf("%s output: %s", name, trimmed)
	}
	return nil
}

// IsTunRunning returns true if TUN is currently running
func IsTunRunning() bool {
	return tunRunning.Load()
}
