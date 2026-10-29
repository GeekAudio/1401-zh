import json
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
print(f'''新增 App 自动更新：启动后自动检查本仓库正式版，运行期间每小时复查。发现新版后自动下载 GitHub ZIP，通过 SHA-256、独立签名、Bundle ID、版本和代码签名校验后，备份、替换并重新打开 App。

有安装、日志采集、EFI 操作、USB 监测或授权窗口时先等待，任务结束后再替换。自动与手动更新去重，失败保留当前 App 并退避重试；兼容 GitHub API 限流时的公开 Release 检查。只自动更新 App，驱动安装更新及诊断上传保留原流程。

SwiftUI / AppKit 原生中文界面，保留原版全部 5 个页面与内容。采用灰绿色调、顶部标签、分层面板和有主次的柔和按钮，并支持深浅色。窗口内容区固定为 820 × 600 pt，不支持拉伸、最大化或全屏，长内容在内部滚动。只有 App 自身更新接入本仓库；驱动下载更新、诊断上传、测试通道和其他功能保持作者原有实现。

上游源码：nullmoth/1401@{state['upstream_sha'][:12]}。本仓库只发布 App，驱动由 App 从作者原有地址下载与更新。

下载 ZIP 解压后移到“应用程序”，或使用 DMG。App 为 ad-hoc 签名，未作 Apple 公证。云端测试通过不代表目标显卡的显示、应用和睡眠唤醒已验证。

原始安装器版权归 NullMoth Systems，遵循 PolyForm Noncommercial 1.0.0，限非商业用途。''')
