package ui

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
	"github.com/Locon213/Mimic-App/geo"
	"github.com/Locon213/Mimic-App/service"
)

// ServerConfig represents a saved server configuration
type ServerConfig struct {
	Name        string `json:"name"`
	URL         string `json:"url"`
	Domains     string `json:"domains"`
	CountryCode string `json:"country_code"`
	Flag        string `json:"-"` // Computed field
}

// UpdateFlag computes the flag emoji from the URL
func (s *ServerConfig) UpdateFlag() {
	s.Flag = geo.GetFlagForURL(s.URL)
}

var (
	vpnSvc           *service.VpnService
	isConnected      = false
	connectBtn       *widget.Button
	modeSelector     *widget.Select
	urlEntry         *widget.Entry
	statusLabel      *widget.Label
	statsLabel       *widget.Label
	connectionStatus *widget.RichText
	mainWindow       fyne.Window
	statsTicker      *time.Ticker
	serversList      *widget.List
	savedServers     []ServerConfig
	dnsEntry         *widget.Entry
	transportSelect  *widget.Select
	domainsEntry     *widget.Entry
	routingSwitch    *widget.Check
	proxyPortEntry   *widget.Entry
	currentServerIdx int
)

const serversConfigFile = "servers.json"

func RunApp() {
	a := app.NewWithID("com.locon213.mimicapp")
	mainWindow = a.NewWindow("Mimic VPN Client")

	vpnSvc = service.NewVpnService()

	// Initialize GeoIP database
	if err := geo.InitDB(); err != nil {
		fmt.Printf("Warning: GeoIP database not loaded: %v\n", err)
	}

	loadServers()

	// Create main UI
	mainContent := createMainUI()

	mainWindow.SetContent(mainContent)
	mainWindow.Resize(fyne.NewSize(500, 700))
	mainWindow.ShowAndRun()
}

func createMainUI() *fyne.Container {
	// URL Input Section with Paste Button
	urlEntry = widget.NewEntry()
	urlEntry.SetPlaceHolder("mimic://uuid@ip:port?domains=example.com#ServerName")
	urlEntry.OnChanged = func(s string) {
		// Auto-parse URL and extract info
	}

	pasteBtn := widget.NewButtonWithIcon("", theme.ContentPasteIcon(), func() {
		if clipboard := fyne.CurrentApp().Clipboard(); clipboard != nil {
			content := clipboard.Content()
			if content != "" {
				urlEntry.SetText(content)
			}
		}
	})
	pasteBtn.Importance = widget.LowImportance

	urlInputBox := container.NewHBox(urlEntry, pasteBtn)

	// Mode Selector
	modeSelector = widget.NewSelect([]string{"Proxy (HTTPS/SOCKS5)", "TUN (Global Routing)"}, nil)
	modeSelector.SetSelected("Proxy (HTTPS/SOCKS5)")

	// Connection Status Indicator
	statusDot := canvas.NewCircle(theme.Color(theme.ColorNameError))
	statusDot.Resize(fyne.NewSize(12, 12))
	connectionStatus = widget.NewRichTextWithText("Disconnected")
	connectionStatus.Segments[0].(*widget.TextSegment).Style.Color = theme.Color(theme.ColorNameError)
	statusBox := container.NewHBox(statusDot, connectionStatus)

	// Stats Display
	statsLabel = widget.NewLabel("↓ 0 B/s  ↑ 0 B/s")
	statsLabel.Alignment = fyne.TextAlignCenter
	statsLabel.Hide()

	// Large Connect Button with Icon
	connectBtn = widget.NewButton("CONNECT", toggleConnection)
	connectBtn.Importance = widget.HighImportance
	connectBtn.Icon = theme.MediaPlayIcon()

	// Connection Panel
	connectionPanel := container.NewVBox(
		widget.NewLabelWithStyle("Server Configuration", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
		widget.NewLabel("Server URL:"),
		urlInputBox,
		widget.NewLabel("Connection Mode:"),
		modeSelector,
		layout.NewSpacer(),
		statusBox,
		statsLabel,
		connectBtn,
	)

	// Servers List Tab
	serversList = createServersList()

	// Settings Tab
	settingsTab := createSettingsTab()

	// About Tab
	aboutTab := createAboutTab()

	// Main Tabs
	tabs := container.NewAppTabs(
		container.NewTabItemWithIcon("Connect", theme.MediaPlayIcon(), connectionPanel),
		container.NewTabItemWithIcon("Servers", theme.FolderIcon(), serversList),
		container.NewTabItemWithIcon("Settings", theme.SettingsIcon(), settingsTab),
		container.NewTabItemWithIcon("About", theme.InfoIcon(), aboutTab),
	)
	tabs.SetTabLocation(container.TabLocationLeading)

	return tabs
}

func createServersList() *fyne.Container {
	// Server List
	serversList = widget.NewList(
		func() int { return len(savedServers) },
		func() fyne.CanvasObject {
			return container.NewHBox(
				widget.NewLabel("🌐"), // Flag placeholder
				widget.NewLabel("Server Name"),
				layout.NewSpacer(),
				widget.NewButtonWithIcon("", theme.DeleteIcon(), nil),
				widget.NewButtonWithIcon("", theme.MediaPlayIcon(), nil),
			)
		},
		func(id widget.ListItemID, item fyne.CanvasObject) {
			if id < len(savedServers) {
				items := item.(*fyne.Container).Objects
				items[0].(*widget.Label).SetText(savedServers[id].Flag)
				items[1].(*widget.Label).SetText(savedServers[id].Name)
				items[3].(*widget.Button).OnTapped = func() {
					deleteServer(id)
				}
				items[4].(*widget.Button).OnTapped = func() {
					connectToServer(id)
				}
			}
		},
	)

	// Add Server Button
	addServerBtn := widget.NewButtonWithIcon("Add Server", theme.ContentAddIcon(), showAddServerDialog)
	addServerBtn.Importance = widget.HighImportance

	// Servers Panel
	serversPanel := container.NewBorder(
		nil,
		container.NewVBox(layout.NewSpacer(), addServerBtn),
		nil,
		nil,
		serversList,
	)

	return serversPanel
}

func createSettingsTab() *fyne.Container {
	// DNS Settings
	dnsEntry = widget.NewEntry()
	dnsEntry.SetText("1.1.1.1:53")
	dnsEntry.SetPlaceHolder("DNS Server (e.g., 8.8.8.8:53)")

	// Transport Selection
	transportSelect = widget.NewSelect([]string{"mtp", "tcp"}, nil)
	transportSelect.SetSelected("mtp")

	// Domains for Masking
	domainsEntry = widget.NewMultiLineEntry()
	domainsEntry.SetPlaceHolder("vk.com,yandex.ru,rutube.ru")
	domainsEntry.SetMinRowsVisible(3)

	// Proxy Port
	proxyPortEntry = widget.NewEntry()
	proxyPortEntry.SetText("1080")
	proxyPortEntry.SetPlaceHolder("SOCKS5 Port")

	// Routing Toggle
	routingSwitch = widget.NewCheck("Enable Smart Routing (Direct for local domains)", nil)
	routingSwitch.Checked = true

	// Auto-Reconnect
	autoReconnect := widget.NewCheck("Auto-Reconnect on connection loss", nil)
	autoReconnect.Checked = true

	// Start on Boot
	startOnBoot := widget.NewCheck("Start with system boot", nil)

	// System Tray
	trayIcon := widget.NewCheck("Show in system tray", nil)
	trayIcon.Checked = true

	// Clear Data Button
	clearDataBtn := widget.NewButton("Clear Saved Servers", func() {
		dialog.ShowConfirm("Confirm", "Are you sure you want to clear all saved servers?",
			func(ok bool) {
				if ok {
					savedServers = []ServerConfig{}
					saveServers()
					serversList.Refresh()
				}
			}, mainWindow)
	})
	clearDataBtn.Importance = widget.DangerImportance

	settingsContent := container.NewVBox(
		widget.NewLabelWithStyle("Network Settings", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
		widget.NewLabel("DNS Server:"),
		dnsEntry,
		widget.NewLabel("Transport Protocol:"),
		transportSelect,
		widget.NewLabel("Masking Domains (comma-separated):"),
		domainsEntry,
		widget.NewLabel("SOCKS5 Proxy Port:"),
		proxyPortEntry,
		layout.NewSpacer(),
		widget.NewLabelWithStyle("Advanced Settings", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
		routingSwitch,
		autoReconnect,
		startOnBoot,
		trayIcon,
		layout.NewSpacer(),
		clearDataBtn,
	)

	return container.NewScroll(settingsContent)
}

func createAboutTab() *fyne.Container {
	versionLabel := widget.NewLabel("Version 2.0.0")
	versionLabel.TextStyle = fyne.TextStyle{Bold: true}
	versionLabel.Alignment = fyne.TextAlignCenter

	developerLabel := widget.NewLabel("Developer: Locon213")
	developerLabel.Alignment = fyne.TextAlignCenter

	sdkVersion := widget.NewLabel(fmt.Sprintf("Mimic Protocol SDK: %s", vpnSvc.GetVersion()))
	sdkVersion.Alignment = fyne.TextAlignCenter

	githubLink := widget.NewHyperlink("Official GitHub Repository", parseURL("https://github.com/Locon213/Mimic-Protocol"))
	githubLink.Alignment = fyne.TextAlignCenter

	protocolInfo := widget.NewLabelWithStyle("Protocol Information", fyne.TextAlignLeading, fyne.TextStyle{Bold: true})

	protocolDetails := container.NewVBox(
		widget.NewLabel("• MTP (Mimic Transport Protocol)"),
		widget.NewLabel("• Dynamic domain switching for DPI bypass"),
		widget.NewLabel("• Built-in traffic obfuscation"),
		widget.NewLabel("• Smart routing with direct/proxy rules"),
	)

	aboutContent := container.NewVBox(
		widget.NewIcon(theme.SoftwareIcon()),
		widget.NewLabelWithStyle("Mimic VPN Client", fyne.TextAlignCenter, fyne.TextStyle{Bold: true, SizeName: theme.SizeNameHeadingText}),
		versionLabel,
		sdkVersion,
		layout.NewSpacer(),
		developerLabel,
		githubLink,
		layout.NewSpacer(),
		protocolInfo,
		protocolDetails,
	)

	return container.NewCenter(aboutContent)
}

func showAddServerDialog() {
	nameEntry := widget.NewEntry()
	nameEntry.SetPlaceHolder("My Server")

	urlEntryDialog := widget.NewEntry()
	urlEntryDialog.SetPlaceHolder("mimic://uuid@ip:port?domains=example.com#Name")

	domainsEntry := widget.NewEntry()
	domainsEntry.SetPlaceHolder("vk.com,yandex.ru (optional)")

	form := widget.NewForm(
		widget.NewFormItem("Server Name", nameEntry),
		widget.NewFormItem("Server URL", urlEntryDialog),
		widget.NewFormItem("Domains", domainsEntry),
	)

	dialog.ShowCustomConfirm("Add New Server", "Add", "Cancel", form,
		func(ok bool) {
			if ok && nameEntry.Text != "" && urlEntryDialog.Text != "" {
				server := ServerConfig{
					Name:    nameEntry.Text,
					URL:     urlEntryDialog.Text,
					Domains: domainsEntry.Text,
				}
				server.UpdateFlag()
				server.CountryCode = geo.GetCountryCodeFromURL(urlEntryDialog.Text)

				savedServers = append(savedServers, server)
				saveServers()
				serversList.Refresh()
			}
		}, mainWindow)
}

func deleteServer(id int) {
	if id >= 0 && id < len(savedServers) {
		dialog.ShowConfirm("Confirm Delete",
			fmt.Sprintf("Delete server \"%s\"?", savedServers[id].Name),
			func(ok bool) {
				if ok {
					savedServers = append(savedServers[:id], savedServers[id+1:]...)
					saveServers()
					serversList.Refresh()
				}
			}, mainWindow)
	}
}

func connectToServer(id int) {
	if id >= 0 && id < len(savedServers) {
		server := savedServers[id]
		urlEntry.SetText(server.URL)
		currentServerIdx = id

		// Auto-connect
		if !isConnected {
			toggleConnection()
		}
	}
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
		connectBtn.Icon = theme.MediaPlayIcon()
		updateConnectionStatus("Disconnected", false)
		statsLabel.Hide()
	} else {
		// Connect
		serverURL := urlEntry.Text
		if serverURL == "" {
			dialog.ShowError(fmt.Errorf("please enter a server URL"), mainWindow)
			return
		}

		err := vpnSvc.StartService(serverURL, modeSelector.Selected)
		if err != nil {
			dialog.ShowError(fmt.Errorf("connection failed: %v", err), mainWindow)
			return
		}

		isConnected = true
		connectBtn.SetText("DISCONNECT")
		connectBtn.Importance = widget.DangerImportance
		connectBtn.Icon = theme.MediaStopIcon()
		updateConnectionStatus("Connected", true)
		statsLabel.Show()

		// Start stats update
		statsTicker = time.NewTicker(1 * time.Second)
		go updateStats(statsTicker)
	}
}

func updateConnectionStatus(status string, connected bool) {
	connectionStatus.Segments[0].(*widget.TextSegment).Text = status
	if connected {
		connectionStatus.Segments[0].(*widget.TextSegment).Style.Color = theme.Color(theme.ColorNameSuccess)
	} else {
		connectionStatus.Segments[0].(*widget.TextSegment).Style.Color = theme.Color(theme.ColorNameError)
	}
	connectionStatus.Refresh()
}

func updateStats(ticker *time.Ticker) {
	var lastSent, lastRecv int64
	for range ticker.C {
		if !isConnected {
			return
		}
		stats := vpnSvc.Stats()
		speedSent := stats.UploadSpeed - lastSent
		speedRecv := stats.DownloadSpeed - lastRecv

		statsLabel.SetText(fmt.Sprintf("↓ %s/s  ↑ %s/s\nTotal: ↓ %s  ↑ %s",
			formatBytes(uint64(speedRecv)), formatBytes(uint64(speedSent)),
			formatBytes(uint64(stats.TotalDownload)), formatBytes(uint64(stats.TotalUpload))))

		lastSent = stats.UploadSpeed
		lastRecv = stats.DownloadSpeed
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

func parseURL(u string) *url.URL {
	uri, _ := url.Parse(u)
	return uri
}

func loadServers() {
	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = "."
	}
	configDir = filepath.Join(configDir, "MimicApp")
	os.MkdirAll(configDir, 0755)

	filePath := filepath.Join(configDir, serversConfigFile)
	data, err := os.ReadFile(filePath)
	if err != nil {
		savedServers = []ServerConfig{}
		return
	}

	json.Unmarshal(data, &savedServers)

	// Update flags for all servers
	for i := range savedServers {
		savedServers[i].UpdateFlag()
	}
}

func saveServers() {
	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = "."
	}
	configDir = filepath.Join(configDir, "MimicApp")
	os.MkdirAll(configDir, 0755)

	filePath := filepath.Join(configDir, serversConfigFile)

	// Update country codes before saving
	for i := range savedServers {
		savedServers[i].CountryCode = geo.GetCountryCodeFromURL(savedServers[i].URL)
	}

	data, _ := json.MarshalIndent(savedServers, "", "  ")
	os.WriteFile(filePath, data, 0644)
}
