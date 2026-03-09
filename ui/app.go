package ui

import (
	"fmt"
	"net/url"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/widget"
	"github.com/Locon213/Mimic-App/service"
)

var (
	vpnSvc       *service.VpnService
	isConnected  = false
	connectBtn   *widget.Button
	modeSelector *widget.Select
	urlEntry     *widget.Entry
	statusLabel  *widget.Label
	statsLabel   *widget.Label
	mainWindow   fyne.Window
	statsTicker  *time.Ticker
)

func RunApp() {
	a := app.NewWithID("com.locon213.mimicapp")
	mainWindow = a.NewWindow("Mimic Client")

	vpnSvc = service.NewVpnService()

	urlEntry = widget.NewEntry()
	urlEntry.SetPlaceHolder("mimic://...#ServerName")

	modeSelector = widget.NewSelect([]string{"Proxy (HTTPS/SOCKS5)", "TUN (Global Routing)"}, nil)
	modeSelector.SetSelected("Proxy (HTTPS/SOCKS5)")

	statusLabel = widget.NewLabel("Status: Disconnected")
	statsLabel = widget.NewLabel("0 B/s / 0 B/s")
	statsLabel.Hide()

	connectBtn = widget.NewButton("CONNECT", toggleConnection)
	connectBtn.Importance = widget.HighImportance

	aboutTab := container.NewVBox(
		widget.NewLabelWithStyle("Mimic Protocol Client", fyne.TextAlignCenter, fyne.TextStyle{Bold: true}),
		widget.NewLabelWithStyle("Version 1.0.0", fyne.TextAlignCenter, fyne.TextStyle{}),
		widget.NewLabel("Developer: Locon213"),
		widget.NewHyperlink("Official GitHub Repository", parseURL("https://github.com/Locon213/Mimic-Protocol")),
	)

	connectionTab := container.NewVBox(
		widget.NewLabel("Server Configuration (URL):"),
		urlEntry,
		widget.NewLabel("Connection Mode:"),
		modeSelector,
		layout.NewSpacer(),
		statusLabel,
		statsLabel,
		connectBtn,
	)

	tabs := container.NewAppTabs(
		container.NewTabItem("VPN", connectionTab),
		container.NewTabItem("About", aboutTab),
	)

	mainWindow.SetContent(tabs)
	mainWindow.Resize(fyne.NewSize(350, 500))
	mainWindow.ShowAndRun()
}

func parseURL(u string) *url.URL {
	uri, _ := url.Parse(u)
	return uri
}

func toggleConnection() {
	if isConnected {
		// Disconnect
		vpnSvc.StopService()
		if statsTicker != nil {
			statsTicker.Stop()
		}
		isConnected = false
		connectBtn.SetText("CONNECT")
		connectBtn.Importance = widget.HighImportance
		statusLabel.SetText("Status: Disconnected")
		statsLabel.Hide()
	} else {
		// Connect
		err := vpnSvc.StartService(urlEntry.Text, modeSelector.Selected)
		if err != nil {
			dialog.ShowError(fmt.Errorf("Connection failed: %v", err), mainWindow)
			return
		}
		isConnected = true
		connectBtn.SetText("DISCONNECT")
		connectBtn.Importance = widget.DangerImportance
		statusLabel.SetText("Status: Connected")
		statsLabel.Show()

		// Start stats update
		statsTicker = time.NewTicker(1 * time.Second)
		go updateStats(statsTicker)
	}
}

func updateStats(ticker *time.Ticker) {
	var lastSent, lastRecv uint64
	for range ticker.C {
		if !isConnected {
			return
		}
		sent, recv := vpnSvc.Stats()
		speedSent := sent - lastSent
		speedRecv := recv - lastRecv

		statsLabel.SetText(fmt.Sprintf("Speed: %s/s ↓ | %s/s ↑\nTotal: %s ↓ | %s ↑",
			formatBytes(speedRecv), formatBytes(speedSent),
			formatBytes(recv), formatBytes(sent)))

		lastSent = sent
		lastRecv = recv
	}
}

func formatBytes(b uint64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}
