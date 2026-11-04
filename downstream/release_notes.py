import json
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
print(f'''同步上游 2.7.1。工具页新增「ARM 应用（可选）」卡片：把只为 Apple 芯片构建的应用翻译后在本机运行，可开启/关闭翻译器、检查本机、翻译、打开与移除，翻译过程显示进度并可取消；安装包经 SHA-256 与 NullMoth 签名校验，原应用不变，副本放在“应用程序 › NullMoth ARM”。若安装盘配置请求了 ARM 应用，首次启动会在卡片上方提示一次，可立即开启或暂不，两种选择都会被记住。开启后 /Library/NullMoth 保持可读，应用无需再执行 chmod 即可启动。此外新增 Mac Pro (2019) 支持（实验性）：由 Apple 固件启动时无需 OpenCore，设置写入 NVRAM，需先关闭 SIP；经 OCLP 安装的机型保留其设定的机型。被 -nvoff 停用的驱动会在概览页说明原因并提供重新启用按钮。

新增 App 自动更新：启动后自动检查本仓库正式版，运行期间每小时复查。发现新版后自动下载 GitHub ZIP，通过 SHA-256、独立签名、Bundle ID、版本和代码签名校验后，备份、替换并重新打开 App。

有安装、日志采集、EFI 操作、USB 监测或授权窗口时先等待，任务结束后再替换。自动与手动更新去重，失败保留当前 App 并退避重试；兼容 GitHub API 限流时的公开 Release 检查。App 和驱动更新检查、校验文件、签名文件及下载在 GitHub 直连失败后会重试公开代理 `gh-proxy.com`。App ZIP 使用本分支 Ed25519 密钥验证；驱动包使用上游 NullMoth Ed25519 密钥验证，并保留 SHA-256 校验。代理是第三方中转服务，可能处理请求地址和访问记录；下载内容仍需通过对应签名验证。只自动更新 App，不自动安装或更新驱动，诊断上传保留原流程。

SwiftUI / AppKit 原生中文界面，保留原版全部 5 个页面与内容。采用灰绿色调、顶部标签、分层面板和有主次的柔和按钮，并支持深浅色。窗口宽度固定为 820 pt，高度随页面内容自适应；内容较长时限制在屏幕可用高度并在窗口内部滚动，不提供最大化或全屏。只有 App 自身更新接入本仓库；驱动下载与安装、诊断上传、测试通道及其他操作保留作者原有流程。

上游源码：nullmoth/1401@{state['upstream_sha'][:12]}。本仓库只发布 App；驱动仍从作者原有地址下载，网络失败时才重试公开代理。

下载 ZIP 解压后移到“应用程序”，或使用 DMG。App 为 ad-hoc 签名，未作 Apple 公证。云端测试通过不代表目标显卡的显示、应用和睡眠唤醒已验证。

原始安装器版权归 NullMoth Systems，遵循 PolyForm Noncommercial 1.0.0，限非商业用途。''')
