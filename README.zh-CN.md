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
- 可配置帧率：30、60、120，或“自动”（跟随屏幕刷新率）。任何帧率下墨水流动速度都一致。
- 电池省电（默认开启）：使用电池供电或开启低电量模式时以 30 fps 运行。
- 调色板模式：启动时随机、历代循环、Splatoon 1、Splatoon 2、Splatoon 3，
  或自定义暖色/冷色。
- 历代循环间隔可配置：30、60、90、120 秒，默认 60 秒。
- 无声音。

## 系统要求

- macOS 13 Ventura 或更新版本。
- 支持 Metal 的 Mac。
- Release 产物由 GitHub Actions 构建，是同时支持 Apple 芯片和 Intel 的通用
  二进制。目前只在 Apple 芯片上测试过；如果某个 release build 无法在你的 Mac
  上加载，可以从源码本地构建。

## 开始使用

1. **下载并解压**：从 [latest GitHub Release](https://github.com/space4yyy/splatoon3screensaver/releases/latest)
   下载 `splatoon3-boot.saver.zip`，解压后获得 `splatoon3-boot.saver`。
2. **清除隔离标记**：该屏幕保护程序只有 ad-hoc 签名，没有经过 Apple 公证。macOS
   会给下载的文件加上隔离标记，Gatekeeper 可能因此拒绝打开它（提示 Apple 无法验证
   其不含恶意软件），或阻止它运行（预览黑屏）。安装前请在“终端”里运行下面的命令；
   如果解压到了别的位置，请相应修改路径：
   ```sh
   xattr -cr ~/Downloads/splatoon3-boot.saver
   ```
   如果已经安装，请改为按安装位置运行对应命令：
   - **仅为当前用户安装**：
     ```sh
     xattr -cr ~/Library/Screen\ Savers/splatoon3-boot.saver
     ```
   - **为所有用户安装**：
     ```sh
     sudo xattr -cr /Library/Screen\ Savers/splatoon3-boot.saver
     ```

   请只对本项目 release 中下载的文件这样做；可以把 `shasum -a 256 splatoon3-boot.saver.zip`
   的结果与 release 资源旁显示的 `sha256` 摘要对比。
3. **安装**：双击 `splatoon3-boot.saver` 安装。macOS 会提示选择：
   - **仅为当前用户安装**：安装到 `~/Library/Screen Savers/`
   - **为所有用户安装**：安装到 `/Library/Screen Savers/`，需要管理员密码

4. **选择并配置**：打开 **系统设置**，进入 **墙纸 / 屏幕保护程序**，选择
   **Splatoon 3 Boot**，点击 **选项** 调整墨水配色、历代循环、初始图案、帧率和电池省电。

   在 macOS 26 及更新版本中，如果在同一次打开的系统设置里关掉再重新进入屏幕保护程序
   面板，**选项** 会点不开。这是系统设置的 bug，其他第三方屏保也会遇到。退出系统设置
   （⌘Q）后重新打开，再点 **选项** 即可。

卸载时，删除 `~/Library/Screen Savers`（为所有用户安装时是 `/Library/Screen Savers`）里的
`splatoon3-boot.saver` 即可。

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
- 完整安装 Xcode，并确保 `xcrun`、`metal`、`swiftc` 可用。Xcode 26 及更新版本
  需要单独下载 Metal 编译器；如果 `make` 提示缺少 Metal Toolchain，请运行：

```sh
xcodebuild -downloadComponent MetalToolchain
```

只构建：

```sh
make
```

构建本地可分发 `.saver` 产物：

```sh
make package
```

本地构建默认只针对运行 `make` 的 Mac 架构。Release 会构建通用二进制，并写入
bundle 版本号：

```sh
make package ARCHS="arm64 x86_64" VERSION=1.0.6
```

为当前用户安装本地构建：

```sh
make install
```

清理构建产物：

```sh
make clean
```

每次推送到 `main` 和每个 pull request，GitHub Actions 都会构建，并把
`splatoon3-boot.saver.zip` 保存为 workflow artifact。推送 tag 时还会发布到
GitHub Releases：

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
- `Sources/PowerMonitor.swift`：检测电池供电和低电量模式，用于电池省电。
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
