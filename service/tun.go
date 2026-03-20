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
	"sync"
	"sync/atomic"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/engine"
)

// WindowsTunBackend represents the TUN backend type for Windows
type WindowsTunBackend string

const (
	// WinTunBackend uses WireGuard's WinTun driver
	WinTunBackend WindowsTunBackend = "wintun"
	// WireGuardNTBackend uses WireGuard NT driver
	WireGuardNTBackend WindowsTunBackend = "wireguard-nt"
	// AutoBackend automatically selects the best available backend
	AutoBackend WindowsTunBackend = "auto"
)

var tunRunning atomic.Bool

var (
	tunRemoteMu    sync.RWMutex
	tunRemoteAddr  string
	linuxBypassMu  sync.Mutex
	linuxBypassCfg linuxBypassRoute
)

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

type linuxBypassRoute struct {
	destination string
	via         string
	dev         string
	ipv6        bool
}

func ConfigureTunRemoteAddress(remote string) {
	tunRemoteMu.Lock()
	defer tunRemoteMu.Unlock()
	tunRemoteAddr = strings.TrimSpace(remote)
}

func configuredTunRemoteAddress() string {
	tunRemoteMu.RLock()
	defer tunRemoteMu.RUnlock()
	return tunRemoteAddr
}

// StartTun2Socks starts tun2socks tunneling to the local Mimic SOCKS5 proxy.
func StartTun2Socks() error {
	return startTun2Socks(
		fmt.Sprintf("tun://%s", getTunDeviceName()),
		1500,
		true,
	)
}

// StartTun2SocksFromFD starts tun2socks against an existing TUN file descriptor.
// This is used by Android VpnService, which creates the TUN interface itself.
func StartTun2SocksFromFD(fd int, mtu int) error {
	if fd <= 0 {
		return fmt.Errorf("invalid TUN file descriptor: %d", fd)
	}
	if mtu <= 0 {
		mtu = 1500
	}

	if err := startTun2Socks(fmt.Sprintf("fd://%d", fd), mtu, false); err != nil {
		_ = os.NewFile(uintptr(fd), "android-vpn-tun").Close()
		return err
	}
	return nil
}

func startTun2Socks(device string, mtu int, configureRoutes bool) error {
	if tunRunning.Load() {
		log.Println("TUN is already running")
		return nil
	}

	log.Println("TUN mode requested. Starting tun2socks engine...")

	// Platform-specific TUN setup
	if configureRoutes && runtime.GOOS == "windows" {
		if err := setupWindowsTun(); err != nil {
			return fmt.Errorf("failed to setup Windows TUN: %w", err)
		}
	}

	key := &engine.Key{
		Proxy:    "socks5://127.0.0.1:1080",
		Device:   device,
		LogLevel: "info",
		MTU:      mtu,
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
	if configureRoutes {
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

// setupWindowsTun sets up Windows TUN adapter with enhanced error handling
func setupWindowsTun() error {
	log.Println("Setting up Windows TUN adapter...")

	// Check if running as administrator
	if !isRunningAsAdmin() {
		return errors.New("TUN mode on Windows requires Administrator rights. Please run as Administrator or use Proxy mode instead")
	}

	// Detect and configure TUN backend
	backend := detectWindowsTunBackend()
	log.Printf("Using Windows TUN backend: %s", backend)

	switch backend {
	case WinTunBackend:
		if err := setupWinTun(); err != nil {
			return fmt.Errorf("WinTun setup failed: %w", err)
		}
	case WireGuardNTBackend:
		if err := setupWireGuardNT(); err != nil {
			return fmt.Errorf("WireGuard NT setup failed: %w", err)
		}
	default:
		// Try WinTun first, fallback to WireGuard NT
		if err := setupWinTun(); err != nil {
			log.Printf("WinTun not available: %v, trying WireGuard NT...", err)
			if err := setupWireGuardNT(); err != nil {
				return fmt.Errorf("no TUN backend available: %w", err)
			}
		}
	}

	log.Println("Windows TUN adapter setup completed successfully")
	return nil
}

// detectWindowsTunBackend detects the best available TUN backend
func detectWindowsTunBackend() WindowsTunBackend {
	// Check for WinTun DLL
	if findWintunDll() != "" {
		return WinTunBackend
	}

	// Check for WireGuard NT
	if isWireGuardNTAvailable() {
		return WireGuardNTBackend
	}

	return AutoBackend
}

// setupWinTun configures WinTun driver
func setupWinTun() error {
	wintunDll := findWintunDll()
	if wintunDll == "" {
		return errors.New("wintun.dll not found in common locations")
	}

	log.Printf("Found WinTun DLL: %s", wintunDll)
	os.Setenv("WINTUN_DLL", wintunDll)

	// Verify DLL is accessible
	if _, err := os.Stat(wintunDll); err != nil {
		return fmt.Errorf("WinTun DLL not accessible: %w", err)
	}

	return nil
}

// setupWireGuardNT configures WireGuard NT driver
func setupWireGuardNT() error {
	// Check if WireGuard NT service is available
	cmd := exec.Command("sc", "query", "WireGuardTunnel")
	if err := cmd.Run(); err != nil {
		return errors.New("WireGuard NT service not found")
	}

	log.Println("WireGuard NT service detected")
	return nil
}

// isWireGuardNTAvailable checks if WireGuard NT is available
func isWireGuardNTAvailable() bool {
	cmd := exec.Command("sc", "query", "WireGuardTunnel")
	return cmd.Run() == nil
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
		log.Printf("Warning: could not find TUN interface for cleanup: %v", err)
		// Try to cleanup by interface name pattern
		cleanupWindowsRoutesByName()
		return
	}

	// Remove IPv4 default route
	if err := runWindowsCommand("route", "delete", windowsTunRouteDest, "mask", windowsTunRouteDest,
		windowsTunIPv4GW, "if", fmt.Sprintf("%d", iface.Index)); err != nil {
		log.Printf("Warning: failed to remove IPv4 route: %v", err)
	}

	// Remove IPv6 default route
	if err := runWindowsCommand("netsh", "interface", "ipv6", "delete", "route", "::/0",
		fmt.Sprintf("interface=%s", iface.Name), windowsTunIPv6GW); err != nil {
		log.Printf("Warning: failed to remove IPv6 route: %v", err)
	}

	// Cleanup WireGuard NT if used
	cleanupWireGuardNT()

	log.Println("Windows TUN routes cleaned up")
}

// cleanupWindowsRoutesByName attempts to cleanup routes by interface name pattern
func cleanupWindowsRoutesByName() {
	// Try common TUN interface names
	names := []string{windowsTunName, "MimicTUN", "WireGuard"}
	for _, name := range names {
		if err := runWindowsCommand("netsh", "interface", "ipv4", "delete", "route", windowsTunRouteDest,
			fmt.Sprintf("interface=%s", name), windowsTunIPv4GW); err == nil {
			log.Printf("Cleaned up routes for interface: %s", name)
		}
	}
}

// cleanupWireGuardNT cleans up WireGuard NT tunnel
func cleanupWireGuardNT() {
	// Stop WireGuard tunnel service if it was started
	cmd := exec.Command("sc", "stop", "WireGuardTunnel")
	if err := cmd.Run(); err != nil {
		// Service might not be running, which is fine
		log.Printf("WireGuard NT service stop: %v", err)
	} else {
		log.Println("WireGuard NT service stopped")
	}
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
	if bypass, err := discoverLinuxBypassRoute(); err != nil {
		log.Printf("Warning: failed to discover Linux bypass route for VPN server: %v", err)
	} else if bypass.destination != "" {
		if err := addLinuxBypassRoute(bypass); err != nil {
			log.Printf("Warning: failed to install Linux bypass route: %v", err)
		}
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
	configureLinuxResolved(iface.Name, true)

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

	configureLinuxResolved(iface.Name, false)
	_ = runSystemCommand("ip", "route", "del", "0.0.0.0/1", "dev", iface.Name)
	_ = runSystemCommand("ip", "route", "del", "128.0.0.0/1", "dev", iface.Name)
	_ = runSystemCommand("ip", "-6", "route", "del", "::/1", "dev", iface.Name)
	_ = runSystemCommand("ip", "-6", "route", "del", "8000::/1", "dev", iface.Name)
	removeLinuxBypassRoute()
}

func cleanupMacOSTun() {
	_ = runSystemCommand("route", "-n", "delete", "-inet", "0.0.0.0/1")
	_ = runSystemCommand("route", "-n", "delete", "-inet", "128.0.0.0/1")
}

func discoverLinuxBypassRoute() (linuxBypassRoute, error) {
	remote := configuredTunRemoteAddress()
	if remote == "" {
		return linuxBypassRoute{}, nil
	}

	host := remote
	if parsedHost, _, err := net.SplitHostPort(remote); err == nil {
		host = parsedHost
	}

	ips, err := net.LookupIP(host)
	if err != nil || len(ips) == 0 {
		return linuxBypassRoute{}, fmt.Errorf("resolve remote host %q: %w", host, err)
	}

	for _, ip := range ips {
		route, routeErr := linuxRouteGet(ip.String())
		if routeErr == nil {
			return route, nil
		}
	}

	return linuxBypassRoute{}, fmt.Errorf("no usable route found for %q", host)
}

func linuxRouteGet(destination string) (linuxBypassRoute, error) {
	args := []string{"route", "get", destination}
	if strings.Contains(destination, ":") {
		args = []string{"-6", "route", "get", destination}
	}

	output, err := runSystemCommandOutput("ip", args...)
	if err != nil {
		return linuxBypassRoute{}, err
	}

	fields := strings.Fields(output)
	route := linuxBypassRoute{ipv6: strings.Contains(destination, ":")}
	for i := 0; i < len(fields); i++ {
		switch fields[i] {
		case "via":
			if i+1 < len(fields) {
				route.via = fields[i+1]
			}
		case "dev":
			if i+1 < len(fields) {
				route.dev = fields[i+1]
			}
		}
	}

	if route.via == "" || route.dev == "" {
		return linuxBypassRoute{}, fmt.Errorf("unexpected ip route output for %q: %s", destination, strings.TrimSpace(output))
	}

	if route.ipv6 {
		route.destination = destination + "/128"
	} else {
		route.destination = destination + "/32"
	}

	return route, nil
}

func addLinuxBypassRoute(route linuxBypassRoute) error {
	if route.destination == "" {
		return nil
	}

	args := []string{"route", "replace", route.destination, "via", route.via, "dev", route.dev, "metric", "1"}
	if route.ipv6 {
		args = append([]string{"-6"}, args...)
	}
	if err := runSystemCommand("ip", args...); err != nil {
		return err
	}

	linuxBypassMu.Lock()
	linuxBypassCfg = route
	linuxBypassMu.Unlock()
	return nil
}

func removeLinuxBypassRoute() {
	linuxBypassMu.Lock()
	route := linuxBypassCfg
	linuxBypassCfg = linuxBypassRoute{}
	linuxBypassMu.Unlock()

	if route.destination == "" {
		return
	}

	args := []string{"route", "del", route.destination, "via", route.via, "dev", route.dev}
	if route.ipv6 {
		args = append([]string{"-6"}, args...)
	}
	_ = runSystemCommand("ip", args...)
}

func configureLinuxResolved(linkName string, enable bool) {
	if !commandExistsInPath("resolvectl") {
		return
	}

	if enable {
		_ = runSystemCommand("resolvectl", "dns", linkName, "1.1.1.1", "8.8.8.8")
		_ = runSystemCommand("resolvectl", "domain", linkName, "~.")
		_ = runSystemCommand("resolvectl", "default-route", linkName, "yes")
		return
	}

	_ = runSystemCommand("resolvectl", "revert", linkName)
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

func runSystemCommandOutput(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s %s failed: %w (%s)", name, strings.Join(args, " "), err, strings.TrimSpace(string(output)))
	}
	return string(output), nil
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

func commandExistsInPath(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// IsTunRunning returns true if TUN is currently running
func IsTunRunning() bool {
	return tunRunning.Load()
}
