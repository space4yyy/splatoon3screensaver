## Install

1. Download `splatoon3-boot.saver.zip` below and unzip it.
2. This screen saver is not notarized, so remove the quarantine flag macOS adds to downloads (see **Not notarized**). Adjust the path if you unzipped it elsewhere:
   ```sh
   xattr -cr ~/Downloads/splatoon3-boot.saver
   ```
3. Double-click `splatoon3-boot.saver` and choose whether to install it for this user or for all users.
4. Open **System Settings > Wallpaper / Screen Saver**, select **Splatoon 3 Boot**, and click **Options** to set the inks, palette cycle, starting pattern, frame rate, and battery saver.

On macOS 26 and later, **Options** stops responding once you close and reopen the screen saver panel in the same System Settings session. This is a System Settings bug that affects other third-party screen savers too. Quit System Settings (⌘Q), open it again, and click **Options**.

To uninstall, delete `splatoon3-boot.saver` from `~/Library/Screen Savers` (or `/Library/Screen Savers` if you installed it for all users).

## Not notarized

The screen saver is ad-hoc signed and not notarized by Apple. Browsers mark downloaded files as quarantined, and Gatekeeper rejects quarantined code it cannot verify, so macOS may:

- refuse to open `splatoon3-boot.saver`, saying Apple could not verify it is free of malware;
- block the installed screen saver from running, so the preview stays black or the screen saver does not start.

Removing the quarantine flag before installing (step 2) avoids both. If you already installed it, run the command for where it is installed:

```sh
xattr -cr ~/Library/Screen\ Savers/splatoon3-boot.saver
```

```sh
sudo xattr -cr /Library/Screen\ Savers/splatoon3-boot.saver
```

If macOS blocks it and **System Settings > Privacy & Security** offers **Open Anyway**, you can allow it there instead; the button stays for about an hour after the blocked attempt.

Only do this for files downloaded from this page. To check the download, compare its SHA-256 with the `sha256` digest shown next to the asset:

```sh
shasum -a 256 ~/Downloads/splatoon3-boot.saver.zip
```

---

## 安装

1. 下载下方的 `splatoon3-boot.saver.zip` 并解压。
2. 这个屏保没有经过 Apple 公证，需要先移除 macOS 给下载文件加的隔离标记（见“未公证说明”）。如果解压到了别的位置，请相应修改路径：
   ```sh
   xattr -cr ~/Downloads/splatoon3-boot.saver
   ```
3. 双击 `splatoon3-boot.saver`，选择仅为当前用户安装或为所有用户安装。
4. 打开 **系统设置 › 墙纸 / 屏幕保护程序**，选择 **Splatoon 3 Boot**，点击 **选项** 设置墨水配色、历代循环、初始图案、帧率和电池省电。

在 macOS 26 及更新版本中，如果在同一次打开的系统设置里关掉再重新进入屏幕保护程序面板，**选项** 会点不开。这是系统设置的 bug，其他第三方屏保也会遇到。退出系统设置（⌘Q）后重新打开，再点 **选项** 即可。

卸载时，删除 `~/Library/Screen Savers`（为所有用户安装时是 `/Library/Screen Savers`）里的 `splatoon3-boot.saver` 即可。

## 未公证说明

这个屏保只有 ad-hoc 签名，没有经过 Apple 公证。浏览器下载的文件会被标记为“隔离”，Gatekeeper 会拒绝无法验证的隔离代码，因此 macOS 可能：

- 拒绝打开 `splatoon3-boot.saver`，提示 Apple 无法验证其不含恶意软件；
- 阻止已安装的屏保运行，表现为预览黑屏或屏保无法启动。

安装前先移除隔离标记（第 2 步）就能避免这两种情况。如果已经装好了，按安装位置运行对应命令：

```sh
xattr -cr ~/Library/Screen\ Savers/splatoon3-boot.saver
```

```sh
sudo xattr -cr /Library/Screen\ Savers/splatoon3-boot.saver
```

如果 macOS 拦截后，**系统设置 › 隐私与安全性** 里出现 **仍要打开**，也可以在那里放行；这个按钮在被拦截后大约一小时内有效。

请只对从本页面下载的文件这样做。可以把下载文件的 SHA-256 与资源旁显示的 `sha256` 摘要对比：

```sh
shasum -a 256 ~/Downloads/splatoon3-boot.saver.zip
```
