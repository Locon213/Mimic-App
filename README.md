# Mimic Protocol Client (Official App)

<div align="center">

![Mimic VPN](https://img.shields.io/badge/Mimic-VPN-6366F1?style=for-the-badge&logo=vpn)
![Flutter](https://img.shields.io/badge/Flutter-UI-02569B?style=for-the-badge&logo=flutter)
![Go](https://img.shields.io/badge/Go-Backend-00ADD8?style=for-the-badge&logo=go)
![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-lightgrey?style=for-the-badge)

**Cross-platform VPN client built with Flutter and Go Mobile**

[![Build](https://img.shields.io/github/actions/workflow/status/Locon213/Mimic-App/build.yml?style=flat-square&logo=github)](https://github.com/Locon213/Mimic-App/actions)
[![Release](https://img.shields.io/github/v/release/Locon213/Mimic-App?style=flat-square&logo=github)](https://github.com/Locon213/Mimic-App/releases)
[![License](https://img.shields.io/github/license/Locon213/Mimic-App?style=flat-square&logo=github)](LICENSE)

</div>

---

## 🌟 Features

* **🎨 Beautiful Modern UI** - Inspired by V2RayTun with smooth animations and gradients
* **📱 Full Cross-Platform** - Android, iOS, Windows, macOS, Linux from a single codebase
* **🔒 Secure Connection** - Built on Mimic Protocol SDK with MTP transport
* **⚡ Real-time Statistics** - Live traffic monitoring with download/upload speeds
* **🌍 Server Management** - Save and manage multiple server configurations
* **🔄 Dual Modes**:
  * **Proxy Mode** - HTTPS/SOCKS5 proxy for selective routing
  * **TUN Mode** - Global routing for all device traffic
* **🎯 Smart Routing** - Direct/proxy rules with domain-based routing
* **🌐 DPI Bypass** - Dynamic domain switching for censorship circumvention

---

## 📸 Screenshots

<div align="center">

![Dark Theme](https://via.placeholder.com/300x600/0F172A/6366F1?text=Dark+Theme)
![Light Theme](https://via.placeholder.com/300x600/F8FAFC/6366F1?text=Light+Theme)
![Connection](https://via.placeholder.com/300x600/1E293B/10B981?text=Connected)

</div>

---

## 🏗️ Architecture

```
┌─────────────────────────────────────┐
│         Flutter UI Layer            │
│  (Dart - Cross-platform frontend)   │
├─────────────────────────────────────┤
│      Provider State Management      │
├─────────────────────────────────────┤
│    Go Mobile Bindings (gomobile)    │
├─────────────────────────────────────┤
│       Mimic Protocol SDK (Go)       │
│  ┌──────────────────────────────┐   │
│  │  MTP Transport  │  Proxies   │   │
│  │  TUN2SOCKS      │  Routing   │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

* **Flutter SDK** 3.0+ ([Install](https://docs.flutter.dev/get-started/install))
* **Go** 1.25+ ([Install](https://golang.org/dl/))
* **gomobile** tools
* **Android Studio** / **Xcode** for mobile builds

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/Locon213/Mimic-App.git
cd Mimic-App
```

2. **Install gomobile tools**
```bash
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
gomobile init
```

3. **Install Flutter dependencies**
```bash
cd mimic_app
flutter pub get
```

4. **Build Go Mobile libraries**
```bash
# From project root
chmod +x scripts/build-mobile.sh
./scripts/build-mobile.sh
```

5. **Run the application**
```bash
cd mimic_app
flutter run
```

---

## 📦 Building for Production

### Android
```bash
# Build APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release
```

### iOS
```bash
# Build IPA
flutter build ios --release --no-codesign
```

### Desktop
```bash
# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

---

## ⚙️ Configuration

### Server URL Format
```
mimic://uuid@server:port?domains=example.com#ServerName
```

**Example:**
```
mimic://550e8400-e29b-41d4-a716-446655440000@192.168.1.1:443?domains=vk.com,yandex.ru#MyServer
```

### Connection Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Proxy** | HTTPS/SOCKS5 proxy | Browser extensions, selective apps |
| **TUN** | System-wide tunnel | All device traffic (requires admin/root) |

---

## 🛠️ Development

### Project Structure
```
Mimic-App/
├── mimic_app/              # Flutter application
│   ├── lib/
│   │   ├── main.dart       # App entry point
│   │   ├── screens/        # UI screens
│   │   ├── widgets/        # Reusable widgets
│   │   ├── providers/      # State management
│   │   ├── models/         # Data models
│   │   └── utils/          # Utilities & theme
│   ├── android/            # Android-specific files
│   └── ios/                # iOS-specific files
├── mobile/                 # Go Mobile bindings
│   └── mimic.go            # Mobile-compatible API
├── service/                # Go backend services
│   ├── vpn.go              # VPN service
│   └── tun.go              # TUN2SOCKS integration
├── scripts/                # Build scripts
│   ├── build-mobile.ps1    # PowerShell build script
│   └── build-mobile.sh     # Bash build script
└── .github/workflows/      # CI/CD pipelines
```

### State Management
This app uses **Provider** pattern for state management:
- `VpnProvider` - VPN connection state and statistics
- `ServerProvider` - Server configuration management
- `ThemeProvider` - Light/Dark theme toggle

---

## 🔄 CI/CD

The project uses GitHub Actions for automated builds:

### Workflows
- **build.yml** - Builds on every push/PR
- **release.yml** - Creates release artifacts on new GitHub Release

### Automatic Builds
When you create a new GitHub Release, the workflow will:
1. Build Go Mobile libraries (AAR for Android, XCFramework for iOS)
2. Build Flutter app for all platforms
3. Attach artifacts to the release:
   - `MimicApp-Android.apk`
   - `MimicApp-Android.aab`
   - `MimicApp-iOS.ipa`
   - `MimicApp-Windows.zip`
   - `MimicApp-Linux.tar.gz`
   - `MimicApp-macOS.zip`

---

## 📋 Permissions

### Android
- `INTERNET` - Network access
- `FOREGROUND_SERVICE` - Persistent VPN service
- `BIND_VPN_SERVICE` - VPN functionality
- `POST_NOTIFICATIONS` - Status notifications (Android 13+)
- `RECEIVE_BOOT_COMPLETED` - Auto-start on boot
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` - Background operation

### iOS
- `NSLocalNetworkUsageDescription` - Local network access
- `NetworkExtension` - VPN functionality
- `UIBackgroundModes` - Background operation

---

## 🐛 Troubleshooting

### Common Issues

**Go Mobile build fails:**
```bash
# Ensure gomobile is initialized
gomobile init

# Check Go version (requires 1.25+)
go version
```

**Flutter build fails:**
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter build apk
```

**VPN connection drops:**
- Check server URL format
- Verify network connectivity
- Try switching between Proxy/TUN modes
- Run as Administrator (Windows) or with sudo (Linux/macOS)

---

## 📄 Credits

* **Developer:** Locon213
* **Protocol:** [Mimic Protocol SDK](https://github.com/Locon213/Mimic-Protocol)
* **UI Framework:** [Flutter](https://flutter.dev/)
* **Backend:** [Go](https://go.dev/) + [gomobile](https://pkg.go.dev/golang.org/x/mobile)
* **TUN2SOCKS:** [xjasonlyu/tun2socks](https://github.com/xjasonlyu/tun2socks)

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---



---

<div align="center">

**Built with ❤️ using Flutter & Go**

© 2026 Locon213. All rights reserved.

</div>
