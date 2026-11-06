# Island without push

免费 Apple ID 签的 iPhone App，没有 APNs 推送，也能有 **灵动岛**、**锁屏实时活动（Live Activity）** 和 **后台"推送"（本地通知）**。这个仓库是这三样的最小可用版本：一个 SwiftUI 示例 App、一个 Live Activity 扩展、一个几十行的 Python 长轮询服务器，以及在 GitHub Actions 上构建**未签名 IPA** 的工作流。真机上已经跑通（iPhone 17 / iOS 26，Sideloadly + 免费 Apple ID）。

*English: a free-Apple-ID-signed iOS app with no APNs that still gets a Dynamic Island, a lock-screen Live Activity and "push-like" local notifications. The trick is a silent looped audio track under the `audio` background mode that keeps the app alive, a long poll to your own server, and ActivityKit's `staleDate` as an honest "the app is gone" signal. Build an unsigned IPA on GitHub Actions, sign it yourself with Sideloadly/AltStore.*

## 原理（三句话）

1. **活着**：离开 App 的那一刻起播放一段内存里生成的 1 秒静音 WAV，循环，`UIBackgroundModes: [audio]`，`.mixWithOthers` 不打断用户的音乐。只要它在播，进程就不会被挂起，App 就能继续对服务器长轮询（`App/Standby.swift`、`App/Poller.swift`）。
2. **岛和锁屏**：`ActivityKit` 的 Live Activity 不需要付费账号，扩展只是第二个 App ID。App 在离开前台的那一下启动活动（iOS 只允许可见时启动），之后每次轮询回来就 `update`，每次都把 `staleDate` 设为 5 分钟后。App 被杀，活动不会消失，但会过期变灰并写"后台掉了"——这是诚实的信号，不是假在线（`App/IslandController.swift`、`Island/IslandLiveActivity.swift`）。
3. **通知**：没有 APNs，就在后台轮询到新消息时发 **本地通知**。按 id 去重，装上后第一次拿到的旧消息不补发，App 在前台时不弹（`App/Notices.swift`）。

岛上的画是像素网格（文本文件），编译进两个目标，一格 = 整数个点，不插值，不走 App Groups（`Shared/PixelArt.swift`，由 `tools/make_pixel_art.py` 从 `art/` 生成）。

## 诚实的限制

- **只有 App 还在后台活着时才有这一切。** 用户手动上滑杀掉 App、系统因为内存回收、或者静音音频被打断又没恢复，轮询就停了，通知不再来，岛在 5 分钟后变灰。这不是推送，是"没睡着"。
- 后台持续放静音会**耗电**，电池设置里会看到它。这是代价，不是 bug。
- 免费 Apple ID：签名 **7 天**过期；每 7 天最多 **10 个 App ID**，这个 App 用掉 2 个（主 App + 扩展）。
- Live Activity 需要 iOS 16.2+；灵动岛需要有岛的机型，没有岛的机型只有锁屏那一块。
- 当另一个 App 也有实时活动时，两个都缩成小圆圈（minimal），所以 `minimalCrop` 要裁出你的画里最认得出的一块。
- iOS 只允许 App **可见时**启动活动。所以活动在"离开 App 的那一下"启动；如果那一刻待机没在播或者系统拒绝，就等下一次离开。
- 别的 App 开始录音/通话时，静音播放会被打断；`AVAudioSession.interruptionNotification` 结束后会自动恢复。

## 快速开始

1. Fork 或下载。把 `project.yml` 里的两个 bundle id（`dev.example.islanddemo`、`dev.example.islanddemo.island`）改成你自己的。
2. GitHub → **Actions → Build unsigned IPA → Run workflow**。几分钟后在 Artifacts 下载 `IslandDemo-unsigned`，解压得到 `IslandDemo-unsigned.ipa`。GitHub 不需要你的 Apple ID。
3. 用 [Sideloadly](https://sideloadly.io/)（或 AltStore）把 IPA 装到手机，用你的免费 Apple ID 签。手机上按提示开启开发者模式、信任开发者。
4. 电脑上跑 `python3 server/demo_server.py`（和手机同一个局域网），在 App 里填 `http://<电脑 IP>:8787`。
5. 打开"离开 App 后保持待机"，允许通知，然后上滑回桌面。几秒内岛上出现小苗。
6. 电脑上：

   ```bash
   curl -X POST localhost:8787/say    -d '{"text":"hello from the server"}'    # → 锁屏横幅
   curl -X POST localhost:8787/island -d '{"state":"happy","line":"今天开花了"}'   # → 岛换成开花的苗
   curl -X POST localhost:8787/island -d '{"hide":true}'                          # → 收掉活动
   ```

7. 手动杀掉 App，等 5 分钟：岛变灰，写"后台掉了，点开 App 看看"。这就是它该有的样子。

## 服务端契约

App 只会对一个地址长轮询：

```
GET /status?wait=20
    X-Presence: foreground | background
    X-Standby:  on | off
→ 200 {"island": {"state": "<sprite>", "line": "<≤30 字>", "hide": false},
       "messages": [{"id": "<唯一>", "text": "<≤80 字>", "title": "<可选>"}]}
```

服务器有变化立刻回，没有就等 `wait` 秒再回当前状态。`messages` 给"最近 N 条"即可，App 自己按 `id` 去重。任何一个键缺失或格式错都只会丢掉那一个键，不影响别的（`App/PollModels.swift`，有测试）。

## 换成你自己的画

- `art/palette.json`：字母 → 颜色。`art/pixels/<state>-compact.txt` 收起时的岛（示例 30×21，1 pt 一格），`<state>-wide.txt` 展开和锁屏（示例 90×21，2 pt 一格）。`.` 是透明。
- 加一个状态就是加一对文件；跑 `python3 tools/make_pixel_art.py` 重新生成 `Shared/PixelArt.swift`。CI 会检查生成结果和提交的一致。
- 尺寸随意；在 `Island/IslandLiveActivity.swift` 里调 `compactScale`、`wideScale`、`minimalCrop`。收起的岛左侧区域大约 36 pt 高，别画太高。
- 示例里的小苗是占位，故意画得简单。换成你喜欢的东西。

## 目录

```
App/        示例 App：Standby（静音保活）、Poller（长轮询）、IslandController、Notices、PollModels、界面
Island/     Live Activity 扩展（灵动岛 + 锁屏）
Shared/     两个目标共用：IslandAttributes、PixelArt（生成）
art/        像素画源文件 + 调色板
tools/      make_pixel_art.py
server/     demo_server.py（标准库，长轮询）
Tests/      纯 swiftc 跑的检查，CI 执行
.github/    构建未签名 IPA
```

## 来源

这些代码从我自己一个私有的 iPhone 壳项目里抽出来（2026-11-06 那几版），去掉了通话、网页桥接和那个 App 自己的画与文案。思路本身不新：后台音频保活、长轮询、本地通知、Live Activity 都是公开 API，这里只是把它们在免费签名下拼成一套能用的。

MIT License.
