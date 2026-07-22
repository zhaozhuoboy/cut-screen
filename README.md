# 轻截（CutScreen）

一款原生、轻量的 macOS 菜单栏截图工具。默认按 `Control + Command + A` 唤出，支持窗口识别、自由框选、标注、滚动长截图、桌面贴图、剪贴板和本地保存。

![轻截应用图标](Resources/AppIcon-1024.png)

## 功能

- 菜单栏常驻，无 Dock 图标、无主窗口
- 可修改全局快捷键，默认 `⌃⌘A`
- 登录时启动开关，默认关闭
- 多显示器截图，窗口悬停识别和自由框选
- 矩形、圆形、铅笔、箭头、序号、马赛克
- 固定色板、三档线宽、撤销、重做和删除
- 手动向下滚动并自动拼接长截图
- 置顶桌面贴图，可移动、缩放、复制和保存
- 确认复制 PNG；保存支持 PNG 和 JPEG

## 系统和开发环境

- macOS 13 或更高版本
- Xcode 16 或更高版本
- Swift 6

项目是一个 Swift Package，可直接使用 Xcode 打开 `Package.swift`。为了正确显示应用名称、隐藏 Dock 图标并获得独立的录屏权限身份，日常运行建议先构建标准应用包。

## 构建和运行

```bash
make test
make app
open build/CutScreen.app
```

首次截图时，macOS 会请求“屏幕与系统音频录制”权限。授权后退出并重新打开轻截，再按 `⌃⌘A`。

调试构建可以使用：

```bash
swift build
swift test
```

## 签名、DMG 和公证

不设置签名身份时，`make app` 使用 ad-hoc 签名，适合本机开发。正式发布时传入 Developer ID：

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" make app
make dmg
NOTARY_PROFILE=cutscreen-notary Scripts/notarize.sh
```

公证凭据需提前保存到钥匙串：

```bash
xcrun notarytool store-credentials cutscreen-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "APP_SPECIFIC_PASSWORD"
```

## 使用说明

1. 按 `⌃⌘A` 或点击菜单栏“开始截图”。
2. 单击高亮窗口，或拖拽创建自由选区。
3. 使用选区下方工具栏标注；未选择标注工具时可以移动选区或已有标注。
4. 滚动长截图必须在添加标注前开始。进入后手动向下滚动，点击“完成”或再次按截图快捷键结束。
5. “确认”复制 PNG，“保存”写入本地，“钉在桌面”创建置顶贴图。

滚动长截图限制为垂直向下，最大高度 50,000 像素、最大总像素 150 MP。动态视频、受保护内容和变化幅度过大的页面可能无法可靠拼接。

## 架构

- `App`：应用生命周期、菜单栏和入口协调
- `HotKey` / `Settings`：Carbon 全局快捷键、UserDefaults 和登录项
- `Capture`：ScreenCaptureKit 静态截图、窗口识别和会话状态机
- `Editor` / `Rendering`：选区、矢量标注、工具栏和最终合成
- `Scroll`：8 FPS 区域采集、灰度重叠匹配、磁盘增量条带和内存映射长图
- `Pin` / `Export`：桌面贴图、PNG/JPEG 和剪贴板

应用空闲时不会保留 `SCStream`，截图和滚动会话结束后会立即释放屏幕帧与临时状态。
