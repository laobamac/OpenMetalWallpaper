<div align="center">
  <img src="AppIcon.png" width="180" alt="OpenMetalWallpaper Logo">
  <br><br>
  <h1>OpenMetalWallpaper</h1>
  <h3>点亮你的 macOS 桌面，让每一帧都成为艺术</h3>
  <a href="README-EN.md">
    <img src="https://img.shields.io/badge/English-Docs-blue?style=flat-square" alt="English Docs">
  </a>
</div>

<div align="center">

[![GitHub License](https://img.shields.io/github/license/laobamac/OpenMetalWallpaper?style=flat-square&color=brightgreen)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue?style=flat-square)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange?style=flat-square)](https://swift.org)
[![Build Status](https://img.shields.io/badge/Build-Passing-green?style=flat-square)](https://github.com/laobamac/OpenMetalWallpaper/actions)

</div>

<br>

**OpenMetalWallpaper** 是一个专为 macOS 打造的高性能开源动态壁纸引擎。它基于原生 Metal 和 AVFoundation 技术构建，旨在提供极致流畅的播放体验，同时保持极低的系统资源占用。

除了强大的桌面壁纸功能，本项目还包含一个配套的**动态屏幕保护程序 (ScreenSaver)**，支持将你喜爱的视频壁纸无缝应用为系统屏保。

> [!NOTE]
> 🚧 **开发状态**: 目前完美支持 **视频 (Video)** 格式壁纸，**Web (网页)** 已支持绝大部分交互功能。**Scene (场景)** 壁纸正在积极开发与测试中，可以尝试导入，已经实现简单的骨骼和纹理解析。**暂不支持动态组件，如时钟等**，会逐步添加支持！

> [!WARNING]
> ⚠️ 渲染器和解析脚本不开源，其余上传到仓库内的代码文件遵循 **AGPLv3.0** 开源协议
---

## ✨ 核心功能

### ⭐️ 创意工坊支持！
- 可以登录Steam账号后直接从 **Wallpaper Engine** 创意工坊下载壁纸了！
- 你必须拥有Windows下的Wallpaper Engine

### 🖥️ 桌面动态壁纸
- **原生高性能**: 摒弃 Electron，使用 Swift + Metal 原生开发，CPU/GPU 占用极低。
- **多屏独立控制**: 支持多显示器环境，每块屏幕可单独设置不同的壁纸、音量、缩放模式。
- **丰富的播放控制**:
  - 支持 **0.1x - 2.0x** 倍速播放。
  - 支持 **填充 / 适应 / 拉伸 / 自定义 (平移+缩放)** 等多种画面模式。
  - 视频色彩调节（亮度、对比度、饱和度）。
- **Web 壁纸交互**: 支持加载网页壁纸，并允许鼠标交互（无需隐藏桌面图标！）。
- **智能资源管理**:
  - **内存预加载 (Memory Mode)**: 可将小体积视频载入内存播放，彻底消除磁盘 I/O 带来的循环卡顿。
  - **自动暂停**: 当其他应用全屏或前台激活时自动暂停，释放 GPU 算力。

### 🎞️ 动态屏幕保护程序 (New!)
- **独立配置**: 屏保不再盲目同步桌面，而是由你掌控。
- **专属优化**: 屏保模式下采用了 **0.5x 慢动作播放** 策略，营造更优雅、不干扰的待机氛围，同时大幅降低长时间运行的功耗。
- **无缝集成**: 直接在应用内右键即可将当前视频设为屏保源。

### 📂 兼容性与导入
- **Steam 格式支持**: 完美兼容 Wallpaper Engine 的壁纸格式（包含 `project.json` 的文件夹）。
- **便捷导入**: 支持拖拽文件或文件夹直接导入壁纸库。

---

## 🚀 快速开始

### 1. 安装应用
下载最新的 `OpenMetalWallpaper.dmg`，将应用拖入「应用程序」文件夹。

### 2. 安装屏幕保护程序 (可选)
1. 双击 `OpenMetalScreensaver.saver` 文件。
2. 系统会提示安装，选择安装为“当前用户”或“所有用户”。
3. 在「系统设置 -> 屏幕保护程序」中，找到并选中 **OpenMetalScreensaver**。

### 3. 设置屏保内容
由于 macOS 沙盒限制，屏保需要手动指定内容：
1. 打开 **OpenMetalWallpaper** 主程序。
2. 在壁纸库中，**右键点击** 你想要设为屏保的**视频壁纸**。
3. 选择菜单中的 **「设置为动态屏保」**。
4. 现在，当你的 Mac 进入睡眠或触发屏保时，该视频将以 0.5x 速率优雅播放。

---

## ⚙️ 进阶配置

### 内存预加载 (消除卡顿)
如果你的视频壁纸在循环播放的瞬间出现轻微卡顿，或者你希望减少硬盘读写：
1. 打开应用设置 (Preferences)。
2. 在「性能」一栏中勾选 **"预加载视频到内存"**。
3. *注：此功能对大文件视频可能会占用较多内存，建议仅对短循环视频开启。*

### Web 壁纸交互
想要在桌面上玩游戏或操作网页壁纸？
1. 选中一个 Web 类型壁纸。
2. 在右侧属性面板中，开启 **"允许鼠标互动"**。
3. **重要**: 为了响应鼠标点击，应用必须覆盖桌面图标。系统会自动提示你**隐藏桌面图标**，点击确认即可开启互动模式。

----

## 🤝 贡献

我们非常欢迎社区的贡献！无论是新功能的 Idea、Bug 反馈，还是代码提交 (PR)，都能让这个项目变得更好。

* **Issues**: 遇到问题或有建议？请直接提 Issue。
* **Pull Requests**: 欢迎提交代码修复或新特性。

## 📄 许可证

本项目采用 **AGPLv3** 许可证开源。详情请见 [LICENSE](https://www.google.com/search?q=LICENSE) 文件。

---

<div align="center">
Made with ❤️ by <b>laobamac</b>
</div>
