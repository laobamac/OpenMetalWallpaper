<div align="center">
  <img src="AppIcon.png" width="180" alt="OpenMetalWallpaper Logo">
  <br><br>
  <h1>OpenMetalWallpaper</h1>
  <h3>Light up your macOS desktop, making every frame a piece of art</h3>
  <a href="README.md">
    <img src="https://img.shields.io/badge/简体中文-文档-red?style=flat-square" alt="Chinese Docs">
  </a>
</div>

<div align="center">

[![GitHub License](https://img.shields.io/github/license/laobamac/OpenMetalWallpaper?style=flat-square&color=brightgreen)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue?style=flat-square)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange?style=flat-square)](https://swift.org)
[![Build Status](https://img.shields.io/badge/Build-Passing-green?style=flat-square)](https://github.com/laobamac/OpenMetalWallpaper/actions)

</div>

<br>

**OpenMetalWallpaper** is a high-performance open-source dynamic wallpaper engine built exclusively for macOS. Leveraging native Metal and AVFoundation technologies, it delivers an ultra-smooth playback experience while maintaining minimal system resource usage.

In addition to its powerful desktop wallpaper capabilities, this project also includes a companion **dynamic screensaver** that seamlessly allows you to use your favorite video wallpapers as system screensavers.

> [!NOTE]
> 🚧 **Development Status**: Currently fully supports **Video** format wallpapers. **Web** wallpapers support most interactive features. **Scene** wallpapers are under active development and testing; basic bone and texture parsing is functional. **Dynamic components (e.g., clocks) are not yet supported** and will be added progressively!

> [!WARNING]
> ⚠️ The renderer and parsing scripts are not open source. All other code files uploaded to this repository are licensed under the **AGPLv3.0** open-source license.

---

## ✨ Core Features

### ⭐️ Steam Workshop Support!
- Log in with your Steam account and download wallpapers directly from the **Wallpaper Engine** Steam Workshop!
- You must own Wallpaper Engine on Windows.

### 🖥️ Desktop Dynamic Wallpapers
- **Native High Performance**: Built with Swift + Metal (no Electron), ensuring extremely low CPU/GPU usage.
- **Multi-Monitor Control**: Supports multi-display environments, allowing independent wallpaper, volume, and scaling settings per screen.
- **Rich Playback Controls**:
  - Supports **0.1x - 2.0x** playback speed.
  - Multiple display modes: **Fill / Fit / Stretch / Custom (pan + zoom)**.
  - Video color adjustment (brightness, contrast, saturation).
- **Interactive Web Wallpapers**: Load web-based wallpapers with mouse interaction (requires hiding desktop icons in settings to avoid conflicts).
- **Smart Resource Management**:
  - **Memory Preloading (Memory Mode)**: Load small video files into memory for playback, eliminating loop stutter caused by disk I/O.
  - **Auto-Pause**: Automatically pauses when other apps go full-screen or become active, freeing GPU resources.

### 🎞️ Dynamic Screensaver (New!)
- **Independent Configuration**: The screensaver is no longer tied to your desktop wallpaper—you are in control.
- **Exclusive Optimization**: Screensaver mode uses a **0.5x slow-motion playback** strategy for a more elegant, non-intrusive standby experience while significantly reducing power consumption during extended operation.
- **Seamless Integration**: Right-click any video in the app to set it as the screensaver source.

### 📂 Compatibility & Import
- **Steam Format Support**: Fully compatible with Wallpaper Engine wallpaper formats (folders containing `project.json`).
- **Easy Import**: Drag and drop files or folders directly into the wallpaper library.

---

## 🚀 Quick Start

### 1. Install the App
Download the latest `OpenMetalWallpaper.dmg` and drag the app into your "Applications" folder.

### 2. Install the Screensaver (Optional)
1. Double-click the `OpenMetalScreensaver.saver` file.
2. The system will prompt for installation; choose "Install for this user" or "Install for all users."
3. Go to **System Settings → Screen Saver**, find and select **OpenMetalScreensaver**.

### 3. Set Screensaver Content
Due to macOS sandbox restrictions, screensaver content must be manually specified:
1. Open the **OpenMetalWallpaper** main app.
2. In the wallpaper library, **right-click** the **video wallpaper** you want to use as a screensaver.
3. Select **"Set as Dynamic Screensaver"** from the menu.
4. Now, when your Mac sleeps or triggers the screensaver, the video will play gracefully at 0.5x speed.

---

## ⚙️ Advanced Configuration

### Memory Preloading (Eliminate Stutter)
If your video wallpaper stutters slightly at loop points, or if you want to reduce disk read/write:
1. Open the app preferences.
2. Under the "Performance" section, check **"Preload video into memory"**.
3. *Note: This may use more memory for large video files; recommended for short, looping videos only.*

### Interactive Web Wallpapers
Want to play games or interact with web-based wallpapers on your desktop?
1. Select a Web-type wallpaper.
2. In the right-side property panel, enable **"Allow mouse interaction"**.
3. **Important**: To respond to mouse clicks, the app must overlay desktop icons. The system will automatically prompt you to **hide desktop icons**—click confirm to enable interactive mode.

---

## 🤝 Contributing

We warmly welcome contributions from the community! Whether it's new feature ideas, bug reports, or code submissions (PRs), everything helps make this project better.

* **Issues**: Found a bug or have a suggestion? Please open an Issue.
* **Pull Requests**: Welcome fixes or new features via PR.

## 📄 License

This project is open-source under the **AGPLv3** license. See the [LICENSE](LICENSE) file for details.

---

<div align="center">
Made with ❤️ by <b>laobamac</b>
</div>
