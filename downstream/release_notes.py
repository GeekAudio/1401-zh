import json
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
print(f'''同步上游 2.8（含 2.7.2）。工具页的「ARM 应用（可选）」卡片新增 Homebrew 区域：Homebrew 已不再为 Intel Mac 提供安装器，可在这里一次设置两套 Homebrew —— /opt/homebrew 的 ARM 版安装 Homebrew 的 Apple 芯片软件包并为本机翻译后运行，/usr/local 的 Intel 版原生运行、多数软件包从源码构建。可选择同时安装或只装其一，并指定终端里 `brew` 指向哪一套（`abrew` 始终 ARM，`ibrew` 始终 Intel）。创建文件夹需要一次系统密码，下载、Ruby 与翻译均以当前用户执行；卡片会显示两套 Homebrew 的状态、已翻译程序数，以及 ARM Homebrew 的 Ruby 尚未准备时的提示。安装 Homebrew 软件包时，`bin/` 里的命令立即翻译，附带程序首次运行时翻译，共用的库只翻译一次。

安全：App 与驱动的更新签名现在绑定产品名、版本与 SHA-256（`.bsig`），因此旧版安装包不能顶替新版，也不能顶替别的产品；App 拒绝安装比已安装更旧的驱动包与 ARM 包。root 脚本从 App 内的私有副本运行，并由编译进 App 的哈希校验，密码窗口期间无法被替换。为兼容旧版，发布同时提供 `.sig`，2.7.1 及更早的 App 仍可完成一次升级。

上游 2.8 的其他变化见驱动更新日志：NVIDIA 620 内核模块、MetalFX 背后的 DLSS 4 / 4.5、Metal 4，以及开启光线追踪与帧生成时的显存崩溃与卡顿修复。App 侧：桌面报告会说明本次启动音频驱动是否启动、未启动的原因；App 与驱动运行于 macOS 15 与 macOS 26。

SwiftUI / AppKit 原生中文界面，保留原版全部 5 个页面与内容。采用灰绿色调、顶部标签、分层面板和有主次的柔和按钮，并支持深浅色。窗口宽度固定为 820 pt，高度随页面内容自适应；内容较长时限制在屏幕可用高度并在窗口内部滚动，不提供最大化或全屏。只有 App 自身更新接入本仓库；驱动下载与安装、诊断上传、测试通道及其他操作保留作者原有流程。

上游源码：nullmoth/1401@{state['upstream_sha'][:12]}。本仓库只发布 App；驱动仍从作者原有地址下载，网络失败时才重试公开代理 `gh-proxy.com`。

下载 ZIP 解压后移到“应用程序”，或使用 DMG。App 为 ad-hoc 签名，未作 Apple 公证。云端测试通过不代表目标显卡的显示、应用和睡眠唤醒已验证。

原始安装器版权归 NullMoth Systems，遵循 PolyForm Noncommercial 1.0.0，限非商业用途。''')
