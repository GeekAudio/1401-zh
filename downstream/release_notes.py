import json
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
print(f'''同步上游 2.9：工具页增加中文原生驱动设置、游戏模式、GPU 性能提升、混合显卡与 Ryzen 功耗配置，并接入上游实验驱动和功能选项。驱动设置会先显示具体更改，获得确认后写入并回读校验。实验功能沿用上游说明和授权流程。

安全：App 与驱动的更新签名现在绑定产品名、版本与 SHA-256（`.bsig`），因此旧版安装包不能顶替新版，也不能顶替别的产品；App 拒绝安装比已安装更旧的驱动包与 ARM 包。root 脚本从 App 内的私有副本运行，并由编译进 App 的哈希校验，密码窗口期间无法被替换。为兼容旧版，发布同时提供 `.sig`，2.7.1 及更早的 App 仍可完成一次升级。

上游 2.8 的其他变化见驱动更新日志：NVIDIA 620 内核模块、MetalFX 背后的 DLSS 4 / 4.5、Metal 4，以及开启光线追踪与帧生成时的显存崩溃与卡顿修复。App 侧：桌面报告会说明本次启动音频驱动是否启动、未启动的原因；App 与驱动运行于 macOS 15 与 macOS 26。

SwiftUI / AppKit 原生中文界面，保留原版全部 5 个页面与内容。采用灰绿色调、顶部标签、分层面板和有主次的柔和按钮，并支持深浅色。窗口宽度固定为 820 pt，高度随页面内容自适应；内容较长时限制在屏幕可用高度并在窗口内部滚动，不提供最大化或全屏。只有 App 自身更新接入本仓库；驱动下载与安装、诊断上传、测试通道及其他操作保留作者原有流程。

上游源码：nullmoth/1401@{state['upstream_sha'][:12]}。本仓库只发布 App；驱动仍从作者原有地址下载，网络失败时才重试公开代理 `gh-proxy.com`。

下载 ZIP 解压后移到“应用程序”，或使用 DMG。App 为 ad-hoc 签名，未作 Apple 公证。云端测试通过不代表目标显卡的显示、应用和睡眠唤醒已验证。

原始安装器版权归 NullMoth Systems，遵循 PolyForm Noncommercial 1.0.0，限非商业用途。''')
