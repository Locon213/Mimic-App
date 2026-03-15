package service

import (
	"log"
	"os"
	"sync/atomic"

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

	key := &engine.Key{
		Proxy:    "socks5://127.0.0.1:1080",
		Device:   "tun0", // Typically tun0 for linux/mac, or wintun for windows
		LogLevel: "info",
	}

	// This is a simplified wrapper. Real production usage would need
	// specific OS routing commands run here (e.g., ip route add)
	// to route traffic into the TUN interface.
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

	return nil
}

func StopTun2Socks() {
	if !tunRunning.Load() {
		return
	}

	log.Println("Stopping tun2socks engine...")

	// Recover from potential panic
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Panic in StopTun2Socks: %v\n", r)
		}
	}()

	engine.Stop()
	tunRunning.Store(false)
}

// IsTunRunning returns true if TUN is currently running
func IsTunRunning() bool {
	return tunRunning.Load()
}
