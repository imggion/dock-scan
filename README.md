# Dockscan

<p align="center">
  <img src="dockscan/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Dockscan Icon" width="128" height="128">
</p>

<p align="center">
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-macOS%20app-brightgreen" alt="macOS"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.0-orange" alt="Swift"></a>
</p>

<p align="center">
A native macOS menu bar app to inspect and manage your local Docker environment (containers, images, volumes, networks).<br>
Development in progress.
</p>

<p align="center">
  <img src="dock-scan-screen.png" alt="Dockscan screenshot" width="900">
</p>

## Installation

### Build from source

1. Open `dockscan.xcodeproj` in Xcode.
2. Select the `dockscan` scheme.
3. Run the app (`⌘R`).

## Features

- Menu bar integration (window-style menu bar extra)
- Auto-detects Docker Desktop / Colima socket
- Browse containers, images, volumes, networks
- Start/stop/restart/remove containers
- View container logs and basic details
- Remove images, volumes, networks + volume prune

## Contributing

PRs are welcome. If you change anything related to Docker socket detection or API calls, please test with both Docker Desktop and Colima.

## License

MIT License - see [LICENSE.md](LICENSE.md).
