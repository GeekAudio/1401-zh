# 1401 Mac

简体中文 · [English](README.en.md)

1401 Mac 是 1401 的 macOS 原生社区分支，由 GeekAudio 维护。SwiftUI 与 AppKit 界面支持简体中文、繁體中文和英文，安装、EFI 检查、USB 映射及硬件探测沿用上游实现。

[下载正式版](https://github.com/GeekAudio/1401-macos/releases/latest) · [反馈问题](https://github.com/GeekAudio/1401-macos/issues) · [上游项目](https://github.com/nullmoth/1401)

## 使用

App 启动时会按 macOS 的语言偏好选择简体中文、繁體中文或 English。列表中没有匹配的语言时使用英文。也可以在 macOS 的「系统设置 → 通用 → 语言与地区 → 应用程序」单独设置 1401 Mac 的语言，再重新打开 App。

解压 `1401-Mac-*.zip`，将“1401 Mac.app”放到“应用程序”。NVIDIA 驱动需要 Intel / x86_64、macOS 15 或 26，以及受支持的 NVIDIA 显卡。保持 OpenCore 启动盘连接，依次下载驱动、预览更改、核对记录、安装并重启。安装会备份配置。驱动包仍从作者原有地址下载，并按原流程校验。

## 原生界面

实验性驱动与功能位于「实验」标签。工具页分为「系统与启动」「显示与性能」「应用与权限」。GPU 测量位于「报告」，VMD／RAID 提示位于「问题」。左上角和窗口标题栏都显示 **1401 Mac**。切换标签时，页面沿标签方向滑动，并遵循 macOS 的「减少动态效果」设置。窗口宽度固定为 820 pt，高度随页面内容调整，长页面在窗口内滚动。界面支持浅色和深色外观。

## App 更新

App 更新从本仓库获取，校验 SHA-256、Ed25519 签名、Bundle ID 和版本。更新签名（`.bsig`）绑定产品名、版本和 SHA-256。

App 启动约 5 秒后自动检查本仓库正式版，运行期间每小时复查。发现新版后自动下载 GitHub ZIP，沿用上述全部校验，再备份、替换并重新打开 App。安装、日志采集、EFI 操作、GPU 测量、USB 监测或授权窗口尚未结束时，等待它们结束后再更新；下载期间启动的新任务也会延后最终替换。手动与自动检查共享网络请求和下载锁。GitHub 直连遇到网络错误、限流或服务端错误时，App 与驱动更新检查、校验文件、签名文件及下载都会重试公开代理 `gh-proxy.com`；只转发不含凭据、查询参数的公开 GitHub 地址。App ZIP 仍需通过 SHA-256、独立 Ed25519 签名、Bundle ID 和版本校验；驱动包除上游 `SHA256SUMS.txt` 外，还必须通过 NullMoth Ed25519 签名校验，签名信息会随代理重试保留。第三方中转服务可能处理请求地址和访问记录；文件签名仍由 App 内置的相应公钥验证。GitHub API 不可用时，App 更新也会改从同仓库公开 Release 的固定版本读取校验清单；失败保留当前 App，按小时退避重试，也可手动重试。此功能只自动更新 App，不自动安装或更新驱动。

## 工具与诊断

「显示与性能」提供驱动设置、游戏模式、GPU 性能提升、混合显卡和 Ryzen 功耗。驱动设置在写入前展示具体改动，写入后回读校验。兼容的 Intel Xe 设备运行 macOS 15.8 或 26.7 及相应更新版本时，「实验 → 测试驱动」会显示 WhateverXe。

「应用与权限」可为选定 App 请求麦克风、摄像头等权限。可选的 ARM 应用功能使用 NullMoth 翻译器，在「应用程序 › NullMoth ARM」保存翻译副本。Homebrew 可分别配置为 `/opt/homebrew` 的 ARM 版和 `/usr/local` 的 Intel 版。启动盘预先请求 ARM 应用功能时，首次打开会提示是否启用。

Mac Pro (2019) 从 Apple 固件启动时，可以按上游流程在关闭 SIP 后安装驱动。经 OpenCore Legacy Patcher 安装的机型使用 OCLP 设定的机型。itlwm 网卡缺少 HeliPort 时，本机页会显示连接说明。

这是非商业的社区修改版，与上游官方发行版分开维护。原作者及第三方的版权与许可证保留于 [LICENSE](LICENSE) 和 [NOTICE.md](NOTICE.md)。App 图标由本分支绘制。

EFI 挂载和 USB 监测保留原有文字状态，不显示进度条。日志采集与发送、驱动安装、App 更新、WhateverXe 配置及 GPU 测量显示阶段进度；采集与安装按实际到达的处理阶段推进，上传按已处理报告数推进，不按时间模拟。驱动更新把下载和安装合并为连续总进度；单独下载仍按实际字节显示。完成、失败或取消后收起。进度通知只传递数字，不写额外日志文件，也不改变原有任务、授权、上传及 App 替换流程。

## 上游同步、构建与发布

GitHub Actions 每 10 分钟检查上游 `nullmoth/1401` 主分支，也可在 Actions 手动运行“同步上游并发布 1401 Mac”。有变化时同步完整源码，重新应用 `downstream/` 中文原生界面与接口配置，在 macOS 云端编译，运行测试并发布正式 Release。上游改动使补丁锚点、翻译覆盖、测试或构建不兼容时流程失败，旧版 Release 保留。

每次发布包含 App ZIP、DMG、`.bsig`（绑定产品名、版本与 SHA-256）、供旧版读取一次的 `.sig` 和 SHA256SUMS.txt。App 采用 `上游版本.构建号`，与驱动版本分别比较。App 更新密钥与作者的测试驱动密钥分开，作者的驱动签名校验不变。无需手动合并中文分支，也不依赖另一个 Actions 流程被推送事件再次触发。

Release 不附带驱动原包或构建信息附件。App 的驱动下载与更新仍走作者原有地址。

首次配置需要仓库 Secret `RELEASE_SIGNING_KEY`，值为 Ed25519 原始 32 字节私钥的 Base64；对应公钥保存在 `downstream/release-public-key.txt` 并编入 App。私钥不可提交到仓库。若使用 Developer ID，可另行添加签名与公证；当前产物为 ad-hoc 签名，未作 Apple 公证。

```sh
git remote add upstream https://github.com/nullmoth/1401.git
git fetch upstream main
python3 downstream/apply.py --source-ref upstream/main --build 1
bash mac/build.sh ../dist
python3 downstream/check.py
python3 -m unittest discover -s tests -t . -p 'test_*.py'
```

`downstream/apply.py` 从明确的上游提交重建改造，支持重复执行。`downstream/check.py` 将操作分发、扫描、驱动下载更新、安装卸载、USB、诊断及后台报告等实现与上游逐段比较；剥离列明的进度通知、App 自动更新调度、代理重试与 config.plist 选择器修复后，操作实现和安装脚本须与上游一致。它也校验原版页面结构和每段译文，防止界面改造增删内容或改变原有功能。上游页面内容或补丁锚点变化时，需要核对后再发布。`downstream/state.json` 记录当前源码提交、驱动版本、App 版本和构建号。CI 的编译与界面检查不能证明某块显卡在真实硬件上可启动、显示或完成睡眠唤醒。
