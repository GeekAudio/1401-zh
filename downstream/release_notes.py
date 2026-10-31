import json
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
print(f'''新增 App 自动更新：启动后自动检查本仓库正式版，运行期间每小时复查。发现新版后自动下载 GitHub ZIP，通过 SHA-256、独立签名、Bundle ID、版本和代码签名校验后，备份、替换并重新打开 App。

有安装、日志采集、EFI 操作、USB 监测或授权窗口时先等待，任务结束后再替换。自动与手动更新去重，失败保留当前 App 并退避重试；兼容 GitHub API 限流时的公开 Release 检查。App 和驱动更新检查、校验文件及下载在 GitHub 直连失败后会重试公开代理 `gh-proxy.com`。App ZIP 保留 SHA-256 和独立 Ed25519 签名验证；驱动安装仍由用户发起并沿用上游校验流程。代理是第三方中转服务，可能处理请求地址和访问记录；若驱动校验清单也从代理取得，校验信任同样依赖该服务。只自动更新 App，不自动安装或更新驱动，诊断上传保留原流程。

SwiftUI / AppKit 原生中文界面，保留原版全部 5 个页面与内容。采用灰绿色调、顶部标签、分层面板和有主次的柔和按钮，并支持深浅色。窗口宽度固定为 820 pt，高度随页面内容自适应；内容较长时限制在屏幕可用高度并在窗口内部滚动，不提供最大化或全屏。只有 App 自身更新接入本仓库；驱动下载与安装、诊断上传、测试通道及其他操作保留作者原有流程。

上游源码：nullmoth/1401@{state['upstream_sha'][:12]}。本仓库只发布 App；驱动仍从作者原有地址下载，网络失败时才重试公开代理。

下载 ZIP 解压后移到“应用程序”，或使用 DMG。App 为 ad-hoc 签名，未作 Apple 公证。云端测试通过不代表目标显卡的显示、应用和睡眠唤醒已验证。

原始安装器版权归 NullMoth Systems，遵循 PolyForm Noncommercial 1.0.0，限非商业用途。''')
