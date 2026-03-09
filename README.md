# Mimic Protocol Client (Official App)

Welcome to the **Official Mimic Protocol Client**, built with [Fyne](https://fyne.io/) for cross-platform support across Desktop and Mobile environments.
This application uses the official [Mimic Client SDK](https://github.com/Locon213/Mimic-Protocol) to securely and reliably connect you to your Mimic servers.

**Author / Developer:** Locon213

## Features
* **Cross-Platform:** Works on Windows, macOS, Linux, and Android seamlessly.
* **Modern Interface:** Simple Material-style design for ease of use.
* **Dual Modes:**
  * **Proxy (HTTPS/SOCKS5):** Standard routing with minimal overhead, suitable for browser plugins or systemic proxy.
  * **TUN (Global Routing):** Tunnel all traffic on the device through the Mimic MTP link (Requires Admin/Root Privileges).
* **Live Statistics:** See exactly what speeds and traffic volumes are being processed in real time.

## CI/CD and Building
This repository includes a robust GitHub Actions workflow located in `.github/workflows/release.yml`.
When you create a new GitHub Release in this repository, the workflow will automatically:
1. Extract the release version number automatically.
2. Build the application for Windows, Linux, and macOS.
3. Package the outputs and attach them directly to your GitHub Release as artifacts.

### Manual Builds
If you'd like to build the project locally, ensure you have Go 1.22+ and Fyne CLI installed.

```bash
# Install dependencies
go mod tidy

# Install Fyne package tool
go install fyne.io/fyne/v2/cmd/fyne@latest

# Run the app locally (Dev Mode)
go run main.go

# Package for your local OS
fyne package -release
```

## Credits
* **Locon213** - Creator and Lead Developer of Mimic Protocol.
* Built using the fantastic GUI toolkit, Go Fyne.
