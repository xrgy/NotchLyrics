# NotchLyrics

NotchLyrics 是一个 macOS 菜单栏歌词浮层应用。它会在屏幕顶部刘海附近显示一个胶囊形歌词浮层，读取 Spotify 当前播放状态，并尝试从 LRCLIB 获取歌词。

应用适合在听 Spotify 时常驻后台使用：默认只显示一行当前歌词，鼠标悬停后展开为更完整的控制面板，显示封面、播放控制、当前歌词和下一句歌词。

## 功能

- 菜单栏常驻，不占用 Dock。
- 屏幕顶部刘海附近悬浮歌词浮层。
- 收起态显示单行当前歌词。
- 鼠标悬停展开，显示专辑封面、播放控制和更多歌词信息。
- 支持 Spotify OAuth PKCE 登录。
- 自动轮询 Spotify 当前播放歌曲。
- Spotify Web API 不可用时，可回退读取本地 Spotify App。
- 从 LRCLIB 查询同步歌词。
- 没有同步歌词时，会用纯文本歌词生成近似时间轴。

## 系统要求

- macOS 14 或更新版本。
- Swift 6 工具链。
- Spotify macOS App。
- Spotify Developer App 的 Client ID。

本地 Spotify 回退和播放控制通过 AppleScript 调用 Spotify App。首次使用播放控制时，macOS 可能会请求自动化权限。

## 配置 Spotify

先到 Spotify Developer Dashboard 创建一个 app，并把 Redirect URI 设置为：

```text
http://127.0.0.1:43821/callback
```

然后用下面任一方式提供 `client_id`。

### 方式一：环境变量

```bash
export SPOTIFY_CLIENT_ID=你的_client_id
```

如需改回调端口，也可以设置：

```bash
export SPOTIFY_REDIRECT_PORT=43821
```

### 方式二：配置文件

创建配置文件：

```text
~/Library/Application Support/NotchLyrics/config.json
```

内容示例：

```json
{
  "spotifyClientID": "你的_client_id",
  "redirectPort": 43821
}
```

首次运行后，从菜单栏图标打开菜单，点击“连接 Spotify”，浏览器会打开 Spotify 授权页。授权完成后，token 会保存在：

```text
~/Library/Application Support/NotchLyrics/token.json
```

不要提交或公开本地 token、Spotify Client ID 以及其他个人配置。

## 构建

调试构建：

```bash
swift build
```

release 构建：

```bash
swift build -c release
```

release 产物路径：

```text
.build/release/NotchLyrics
```

如果遇到 SwiftPM 模块缓存或沙盒问题，可以使用仓库本地 module cache：

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache swift build -c release
```

## 运行

直接运行 SwiftPM 构建产物：

```bash
./.build/release/NotchLyrics
```

或者打开仓库内已打包的本地 app bundle：

```bash
open dist/NotchLyrics.app
```

如果修改了源码并希望 `dist/NotchLyrics.app` 使用最新二进制，可以先构建 release，然后替换 bundle 内的可执行文件：

```bash
scripts/package_release.sh 0.1.0
```

这个脚本会重新生成 `dist/NotchLyrics.app`，并在 `release/` 目录下生成可上传到 GitHub Release 的产物：

```text
release/NotchLyrics-0.1.0-macos-arm64
release/NotchLyrics-0.1.0-macos-arm64.zip
```

## 使用方式

1. 启动 NotchLyrics。
2. 打开 Spotify macOS App 并开始播放音乐。
3. 从菜单栏点击 NotchLyrics 图标。
4. 如果已配置 Spotify Client ID，点击“连接 Spotify”完成授权。
5. 顶部浮层会自动显示当前歌词。
6. 鼠标悬停在浮层上，可以展开查看封面和播放控制。

如果没有配置 Spotify Client ID，应用仍会尝试通过本地 Spotify App 读取当前播放歌曲；但 Spotify Web API 登录和远程播放状态能力不可用。

## 项目结构

```text
Package.swift
Sources/
  NotchLyrics/             核心应用逻辑、Spotify 集成、歌词查询和浮层 UI
  NotchLyricsApp/          macOS App 入口
  NotchLyricsSmokeTests/   轻量 smoke test 可执行目标
packaging/Info.plist       app bundle 元数据模板
dist/NotchLyrics.app       本地使用的 app bundle
```

核心文件：

- `AppModel.swift`：应用状态、轮询、歌词进度更新。
- `SpotifyAuthManager.swift`：Spotify OAuth PKCE 登录和 token 存储。
- `SpotifyClient.swift`：Spotify Web API 当前播放状态读取。
- `SpotifyLocalClient.swift`：本地 Spotify AppleScript 读取和播放控制。
- `LRCLibClient.swift`：LRCLIB 歌词查询、LRC 解析和纯文本歌词时间轴生成。
- `NotchOverlayView.swift`：顶部歌词浮层 SwiftUI 视图。
- `NotchPanelController.swift`：浮层 NSPanel 创建、定位和展开动画。
- `MenuBarView.swift`：菜单栏窗口 UI。
- `scripts/package_release.sh`：构建 release 二进制、生成 app bundle 和 GitHub Release 压缩包。

## 验证

当前项目没有标准 `Tests/` target，但包含一个 smoke test 可执行目标。

运行 smoke test：

```bash
env CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache swift run NotchLyricsSmokeTests
```

它会验证：

- Spotify API fallback 路径。
- Spotify 广告响应处理。
- Spotify track ID fallback 生成。
- LRCLIB 同步歌词解析。
- LRCLIB 纯文本歌词时间轴生成。
- 本地 Spotify AppleScript 输出解析。

## 常见问题

### 菜单栏里显示未连接 Spotify

确认已经设置 `SPOTIFY_CLIENT_ID`，或已经创建 `~/Library/Application Support/NotchLyrics/config.json`。如果只想使用本地 Spotify 回退，确认 Spotify App 正在运行并正在播放。

### Spotify 授权失败

检查 Spotify Developer App 的 Redirect URI 是否完全等于：

```text
http://127.0.0.1:43821/callback
```

如果修改了 `redirectPort`，Spotify Developer Dashboard 中的 Redirect URI 也要同步修改。

### 无法控制 Spotify 播放

播放控制依赖本机 Spotify App 和 macOS 自动化权限。确认 Spotify App 正在运行，并在系统设置中允许 NotchLyrics 控制 Spotify。

### 没有歌词

歌词来自 LRCLIB。部分歌曲可能没有同步歌词或匹配失败。应用会尝试多组查询条件，但不能保证每首歌都能找到歌词。

## 开发说明

这是一个 Swift Package Manager 项目，核心库目标为 `NotchLyricsCore`，可执行目标为 `NotchLyrics`。项目尽量使用系统框架，包括 SwiftUI、AppKit、Foundation、Combine 和 Network。

开发时建议保持 UI、状态管理、Spotify 集成和歌词服务分离。逻辑较重的新功能应补充针对性的 SwiftPM 测试，优先覆盖解析、授权辅助逻辑和 API 响应处理。
