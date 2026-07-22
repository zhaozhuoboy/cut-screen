# 轻截（CutScreen）

一款原生、轻量的 macOS 菜单栏截图工具。默认按 `Control + Command + A` 唤出，支持窗口识别、自由框选、标注、滚动长截图、桌面贴图、剪贴板和本地保存。

![轻截应用图标](Resources/AppIcon-1024.png)

## 功能

- 菜单栏常驻，无 Dock 图标、无主窗口
- 启动时自动检查屏幕录制权限；未授权时显示引导页，可一键请求权限并打开对应系统设置
- 可修改全局快捷键，默认 `⌃⌘A`
- 登录时启动开关，默认关闭
- 多显示器截图，窗口悬停识别和自由框选
- 矩形、圆形、铅笔、箭头、序号说明、马赛克、高斯模糊与 2 倍放大镜，标注可自由移动；放大镜使用固定轻量轮廓，无额外属性设置
- 每种标注工具独立设置颜色和三档粗细；马赛克支持笔刷和可缩放矩形，支持撤销、重做和删除
- 截图默认使用 16px 圆角和阴影，可在选区上方实时调整
- 手动向下滚动并自动拼接长截图
- 置顶桌面贴图使用圆角图片卡片承载，带毛玻璃标题栏及关闭、复制和保存操作，可移动、等比缩放并跨 Space 显示
- 确认复制 PNG；保存支持 PNG 和 JPEG
- 菜单栏提供“反馈”入口，可直接打开反馈表单

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

## 发布构建

本地开发默认使用 ad-hoc 签名。DMG 可通过以下命令生成：

```bash
make dmg
```

正式发布所需的签名身份和公证凭据应配置在本机环境或钥匙串中，不要提交到版本库。

### 从 GitHub Actions 手动发布

仓库的“Actions → 发布 macOS 正式包 → Run workflow”支持手动生成通用版 DMG，并创建对应的 GitHub Release。发布时填写版本号、构建号并选择打包模式：

- `unsigned`：无需配置证书。生成的文件名带 `-unsigned`，适合发给朋友内测；首次打开可能需要右键选择“打开”，并在系统“隐私与安全性”中确认。
- `signed-notarized`：使用 Developer ID 签名并提交 Apple 公证，适合正式对外分发。

签名公证模式需要在仓库的“Settings → Secrets and variables → Actions”中配置以下 Secrets：

| Secret | 内容 |
|---|---|
| `MACOS_CERTIFICATE` | Developer ID Application `.p12` 文件的 Base64 文本 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `KEYCHAIN_PASSWORD` | CI 临时钥匙串密码，可自行生成一个强密码 |
| `APPLE_ID` | Apple Developer 账号邮箱 |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | Apple ID 的 App 专用密码 |

可在 macOS 上使用 `base64 -i DeveloperID.p12 | pbcopy` 生成证书 Secret。未签名模式不会读取上述 Secrets。

## 使用说明

1. 按 `⌃⌘A` 或点击菜单栏“开始截图”。
2. 单击高亮窗口，或拖拽创建自由选区。
3. 点击选区下方的标注工具后，可在独立属性条中设置颜色和粗细；属性条不会阻塞绘制，拖动已有标注可调整位置，点击序号可输入说明文字。
4. 滚动长截图必须在添加标注前开始。进入后手动向下滚动，点击“完成”或再次按截图快捷键结束。
5. 双击选区或点击“确认”可复制 PNG；“保存”写入本地，“钉在桌面”创建置顶贴图。

滚动长截图目前仅支持垂直向下。动态视频、受保护内容和变化幅度过大的页面可能无法可靠拼接。

## 隐私说明

截图和标注均在本机完成。应用不包含账号系统、网络上传或云端存储功能。
