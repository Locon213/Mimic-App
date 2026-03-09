package service

import (
	"log"
	"os"

	"github.com/xjasonlyu/tun2socks/v2/engine"
)

// tunDevice is handled internally by engine.

// StartTun2Socks starts tun2socks tunneling to the local Mimic SOCKS5 proxy.
func StartTun2Socks() error {
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

	go func() {
		// v2 engine.Start() accepts no arguments.
		// The key must be passed to Insert first.
		engine.Insert(key)
		engine.Start()
	}()

	return nil
}

func StopTun2Socks() {
	log.Println("Stopping tun2socks engine...")
	engine.Stop()
}
