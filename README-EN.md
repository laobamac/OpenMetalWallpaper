<div align="center">
  <img src="AppIcon.png" width="180" alt="OpenMetalWallpaper Logo">
  <br><br>
  <h1>OpenMetalWallpaper</h1>
  <h3>Illuminate Your macOS Desktop, Frame by Frame</h3>
  <br>
</div>

<div align="center">

[![GitHub License](https://img.shields.io/github/license/laobamac/OpenMetalWallpaper?style=flat-square&color=brightgreen)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue?style=flat-square)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange?style=flat-square)](https://swift.org)
[![Build Status](https://img.shields.io/badge/Build-Passing-green?style=flat-square)](https://github.com/laobamac/OpenMetalWallpaper/actions)

</div>

<br>

**OpenMetalWallpaper** is a high-performance, open-source dynamic wallpaper engine built specifically for macOS. It leverages native Metal and AVFoundation technologies to deliver a supremely smooth playback experience while maintaining minimal system resource consumption.

In addition to its powerful desktop wallpaper features, this project includes a complementary **Dynamic Screen Saver**, allowing you to seamlessly apply your favorite video wallpapers as your system's screen saver.

> [!NOTE]
> 🚧 **Development Status**: Currently, **Video** wallpapers are fully supported. **Web** wallpapers now support most interactive features. **Scene** wallpaper support is under active development and testing and is not yet available.

---

## ✨ Core Features

### 🖥️ Desktop Dynamic Wallpaper
- **Native & High Performance**: Ditching Electron, it's built with Swift + Metal for minimal CPU/GPU usage.
- **Multi-Screen Independent Control**: Supports multi-display setups. Configure unique wallpaper, volume, and scaling mode for each screen.
- **Comprehensive Playback Control**:
  - Supports **0.1x - 2.0x** playback speed.
  - Multiple scaling modes: **Fill / Fit / Stretch / Custom (Pan & Zoom)**.
  - Video color adjustment (Brightness, Contrast, Saturation).
- **Web Wallpaper Interaction**: Load webpage wallpapers with mouse interaction support (requires enabling icon hiding in settings to prevent conflicts).
- **Intelligent Resource Management**:
  - **Memory Preload (Memory Mode)**: Load small videos into RAM for playback, eliminating loop stutter caused by disk I/O.
  - **Auto-Pause**: Automatically pauses when another app goes full-screen or is foregrounded, freeing GPU resources.

### 🎞️ Dynamic Screen Saver (New!)
- **Independent Configuration**: Your screen saver is no longer tied to your desktop wallpaper.
- **Purpose-Built Optimization**: In screen saver mode, a **0.5x slow-motion playback** strategy is used for a more elegant, less distracting standby atmosphere, while significantly reducing long-term power consumption.
- **Seamless Integration**: Simply right-click on a video within the main app to set it as the screen saver source.

### 📂 Compatibility & Import
- **Steam Format Support**: Perfectly compatible with Wallpaper Engine's video wallpaper format (folders containing `project.json`).
- **Easy Import**: Drag and drop files or folders directly into the wallpaper library.

---

## 🚀 Quick Start

### 1. Install the Application
Download the latest `OpenMetalWallpaper.dmg` and drag the app to your "Applications" folder.
> [!WARNING]
> 🚧 The project is still in development. No pre-built binaries are released yet. Please clone and compile the repository for testing.

### 2. Install the Screen Saver (Optional)
1. Double-click the `OpenMetalScreensaver.saver` file.
2. The system will prompt for installation. Choose to install for "Current User" or "All Users".
3. In **System Settings > Screen Saver**, find and select **OpenMetalScreensaver**.

### 3. Set Screen Saver Content
Due to macOS sandboxing, the screen saver needs its content specified manually:
1. Launch the main **OpenMetalWallpaper** application.
2. In the wallpaper library, **right-click** on the **video wallpaper** you want to use as your screen saver.
3. Select **"Set as Dynamic Screen Saver"** from the menu.
4. Now, when your Mac sleeps or the screen saver activates, the video will play gracefully at 0.5x speed.

> **Note**: The screen saver feature currently only supports **Video** type wallpapers.

---

## ⚙️ Advanced Configuration

### Memory Preload (Eliminate Stutter)
If your video wallpaper has a slight stutter at the loop point, or you wish to reduce disk activity:
1. Open the app's Preferences.
2. In the "Performance" section, check **"Preload Video into Memory"**.
3. *Note: This may use significant memory for large video files. Recommended for short, looping videos only.*

### Web Wallpaper Interaction
Want to play games or interact with a webpage on your desktop?
1. Select a Web type wallpaper.
2. In the right-side property panel, enable **"Allow Mouse Interaction"**.
3. **Important**: To capture mouse clicks, the app must cover the desktop icons. The system will automatically prompt you to **Hide Desktop Icons**. Click confirm to enable interactive mode.

---

## 🛠️ Development & Build

Developers are warmly welcomed to contribute!

### Prerequisites
- macOS 14.0 (Sonoma) or later
- Xcode 15.0+
- Swift 5.9+

### Build Steps
1. Clone the repository:
   ```
   git clone https://github.com/laobamac/OpenMetalWallpaper.git
   ```
2. Open `OpenMetalWallpaper.xcodeproj`.
3. This is a multi-target project containing:
   * `OpenMetalWallpaper`: The main application.
   * `OpenMetalScreensaver`: The screen saver extension.

4. Ensure you select your own development team in Signing & Capabilities.
5. Press Cmd+R to run.

---

## 🤝 Contributing

Community contributions are highly welcome! Whether it's ideas for new features, bug reports, or code submissions (PRs), everything helps make this project better.

* **Issues**: Found a bug or have a suggestion? Please open an Issue.
* **Pull Requests**: Welcome fixes or new feature implementations.

## 📄 License

This project is open-sourced under the **AGPLv3** license. See the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.

## ❤️ Thank you

[@PIKACHUIM](https://github.com/PIKACHUIM) Great help in debugging/modeling

[@Elysia-best](https://github.com/elysia-best) Great help in debugging/modeling

[@win10Q](https://github.com/win10Q) Great help in mice/touching fish

---

<div align="center">
Made with ❤️ by <b>laobamac</b>
</div>
