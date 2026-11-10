import json
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
print(f'''新增独立的「实验」标签，分为「功能开关」和「测试驱动」。工具页按系统与启动、显示与性能、应用与权限分组。GPU 测量移至「报告」，VMD／RAID 提示移至「问题」。修复「问题」页内容偏左，EFI 检查、结果和存储提示卡片统一左右边距。

同步上游 2.9 后，工具页提供中文原生驱动设置、游戏模式、GPU 性能提升、混合显卡与 Ryzen 功耗配置。驱动设置会先显示具体更改，获得确认后写入并回读校验。实验功能沿用上游说明和授权流程。

安全：App 与驱动的更新签名现在绑定产品名、版本与 SHA-256（`.bsig`），因此旧版安装包不能顶替新版，也不能顶替别的产品；App 拒绝安装比已安装更旧的驱动包与 ARM 包。root 脚本从 App 内的私有副本运行，并由编译进 App 的哈希校验，密码窗口期间无法被替换。为兼容旧版，发布同时提供 `.sig`，2.7.1 及更早的 App 仍可完成一次升级。

上游 2.8 的其他变化见驱动更新日志：NVIDIA 620 内核模块、MetalFX 背后的 DLSS 4 / 4.5、Metal 4，以及开启光线追踪与帧生成时的显存崩溃与卡顿修复。App 侧：桌面报告会说明本次启动音频驱动是否启动、未启动的原因；App 与驱动运行于 macOS 15 与 macOS 26。

SwiftUI / AppKit 原生中文界面保留上游 5 页内容，支持深浅色。窗口宽度固定为 820 pt，高度随页面内容自适应，长页面可在窗口内滚动。App 自身更新接入本仓库。驱动下载与安装、诊断上传和测试通道沿用作者原有流程。

上游源码：nullmoth/1401@{state['upstream_sha'][:12]}。本仓库只发布 App；驱动仍从作者原有地址下载，网络失败时才重试公开代理 `gh-proxy.com`。

下载 ZIP 解压后移到“应用程序”，或使用 DMG。App 为 ad-hoc 签名，未作 Apple 公证。云端测试通过不代表目标显卡的显示、应用和睡眠唤醒已验证。

原始安装器版权归 NullMoth Systems，遵循 PolyForm Noncommercial 1.0.0，限非商业用途。''')
