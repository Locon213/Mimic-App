package service

import (
	"context"
	"errors"
	"log"
	"strings"

	"github.com/Locon213/Mimic-Protocol/pkg/client"
	"github.com/Locon213/Mimic-Protocol/pkg/config"
)

type VpnService struct {
	client *client.Client
	ctx    context.Context
	cancel context.CancelFunc
}

func NewVpnService() *VpnService {
	return &VpnService{}
}

func (v *VpnService) StartService(serverUrl string, mode string) error {
	if serverUrl == "" {
		return errors.New("please enter a server URL")
	}

	cfg, err := config.ParseMimicURL(serverUrl)
	if err != nil {
		return err
	}

	// Always use explicit local proxies for the client.
	cfg.Proxies = []config.ProxyConfig{
		{Type: "socks5", Port: 1080},
		{Type: "http", Port: 1081},
	}
	cfg.DNS = "1.1.1.1:53"

	mimicClient, err := client.NewClient(cfg)
	if err != nil {
		return err
	}

	v.client = mimicClient
	v.ctx, v.cancel = context.WithCancel(context.Background())

	if err := v.client.Start(v.ctx); err != nil {
		return err
	}

	if err := v.client.StartProxies(); err != nil {
		v.client.Stop()
		return err
	}

	if strings.Contains(mode, "TUN") {
		log.Println("TUN mode selected. Starting tun2socks...")
		err := StartTun2Socks()
		if err != nil {
			log.Printf("Failed to start TUN network: %v\n", err)
			return errors.New("failed to start TUN network (try running as Administrator): " + err.Error())
		}
	}

	return nil
}

func (v *VpnService) StopService() {
	StopTun2Socks()
	if v.client != nil {
		v.client.Stop()
		v.client = nil
	}
	if v.cancel != nil {
		v.cancel()
		v.cancel = nil
	}
}

// Stats returns bytes sent and received
func (v *VpnService) Stats() (uint64, uint64) {
	if v.client != nil && v.client.MTP != nil {
		mtpConn := v.client.MTP.GetMTPConn()
		if mtpConn != nil {
			return mtpConn.BytesSent, mtpConn.BytesRecv
		}
	}
	return 0, 0
}
