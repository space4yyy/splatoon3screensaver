# Splatoon 3 Boot Screensaver

[English](README.md) | 简体中文

这是一个原生 macOS `.saver` 屏幕保护程序，复刻 Nick27 在 Shadertoy
发布的 `f3SGWc`，灵感来自 Splatoon 3 的启动动画。

这是非官方粉丝项目，与 Nintendo 无关联，也未获得 Nintendo 认可或赞助。

## 项目介绍

这个屏幕保护程序使用 Metal 渲染多 pass 流体模拟，整体 pass 拓扑与原始
Shadertoy shader 保持一致：

- `Buffer A/B/C`：墨水染料与速度反馈模拟。
- `Buffer D`：泡泡遮罩和调色板阶段状态。
- `Image`：最终颜色合成。

macOS 集成层使用 `ScreenSaverView` 直接驱动 `CAMetalLayer`。这样可以避开
`MTKView` 在系统设置里的生命周期问题，并在 Retina 屏、外接显示器和多 GPU
环境下更稳定。

主要功能：

- 原生 Metal 渲染器。
- 可配置 FPS 上限：30、60、120，或跟随显示器刷新。
- 调色板模式：启动时随机、历代循环、Splatoon 1、Splatoon 2、Splatoon 3，
  或自定义暖色/冷色。
- 历代循环间隔可配置：30、60、90、120 秒，默认 60 秒。
- 无声音。

## 系统要求

- macOS 13 Ventura 或更新版本。
- GitHub Actions 预构建产物面向支持 Metal 的 Apple silicon Mac。
- 支持 Metal 的 Intel Mac 可以从源码本地构建；默认 Makefile 会按运行
  `make` 的 Mac 架构构建。

## 开始使用

1. **下载并解压**：从 GitHub Actions artifacts 下载最新构建产物，解压后获得
   `splatoon3-boot.saver`。
2. **安装**：双击 `splatoon3-boot.saver` 安装。macOS 会提示选择：
   - **仅为当前用户安装**：安装到 `~/Library/Screen Savers/`
   - **为所有用户安装**：安装到 `/Library/Screen Savers/`，需要管理员密码

3. **清除隔离标记**：由于该屏幕保护程序不是通过 Mac App Store 分发，macOS
   Gatekeeper 可能会阻止运行。根据安装位置，在“终端”里运行对应命令：
   - **仅为当前用户安装**：
     ```sh
     xattr -cr ~/Library/Screen\ Savers/splatoon3-boot.saver
     ```
   - **为所有用户安装**：
     ```sh
     sudo xattr -cr /Library/Screen\ Savers/splatoon3-boot.saver
     ```

4. **选择并配置**：打开 **系统设置**，进入 **墙纸 / 屏幕保护程序**，选择
   **Splatoon 3 Boot**，点击 **选项** 调整颜色、帧率、历代循环和初始模拟状态。

## 日志反馈

屏幕保护程序通过 macOS Unified Logging 输出诊断日志。

Subsystem：

```text
ink.space4.Splatoon3Screensaver
```

反馈问题时，请先复现问题，然后运行：

```sh
log show --last 10m --predicate 'subsystem == "ink.space4.Splatoon3Screensaver"' --style compact --info --debug
```

开发时查看实时日志：

```sh
log stream --predicate 'subsystem == "ink.space4.Splatoon3Screensaver"' --style compact --info --debug
```

也可以打开 Console.app，搜索 `ink.space4.Splatoon3Screensaver`。

## 面向开发者 Build

要求：

- macOS 13 或更新版本。
- 完整安装 Xcode，并确保 `xcrun`、`metal`、`swiftc` 可用。

只构建：

```sh
make
```

构建本地可分发 `.saver` 产物：

```sh
make package
```

为当前用户安装本地构建：

```sh
make install
```

清理构建产物：

```sh
make clean
```

推送 tag 后，GitHub Actions 会构建并上传 `.saver` workflow artifact：

```sh
git tag v1.0.0
git push origin v1.0.0
```

重要文件：

- `Sources/Splatoon3ScreensaverView.swift`：`ScreenSaverView` 生命周期和
  `CAMetalLayer` 初始化。
- `Sources/Renderer.swift`：Metal pipeline 创建、反馈纹理和帧渲染。
- `Sources/ConfigSheetController.swift`：选项面板 UI。
- `Sources/Settings.swift`：`ScreenSaverDefaults` 持久化。
- `Shaders/Splatoon3.metal`：shader passes。
- `Resources/bubble-mask.raw`：从原始 Shadertoy `Buffer D` 解码出的
  256x128 泡泡遮罩。
- `Resources/Info.plist`：bundle identifier 和屏幕保护程序元数据。

Bundle identifier 和日志 subsystem：

```text
ink.space4.Splatoon3Screensaver
```

## 致谢

- 原始 Shadertoy shader：`f3SGWc`，
  "[Splatoon 3 Boot animation](https://www.shadertoy.com/view/f3SGWc)"，
  作者 [Nick27](https://www.shadertoy.com/user/Nick27)
- Splatoon 是 Nintendo 的商标。
- 本仓库是非官方粉丝项目。
