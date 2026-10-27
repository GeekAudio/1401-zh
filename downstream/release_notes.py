import json
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
print(f'''移除 EFI 挂载和 USB 监测的进度条。日志采集与发送、驱动安装、App 更新和 GPU 测量改用百分比进度条：按实际阶段和已处理报告数推进，标明阶段进度，不按时间模拟。驱动更新的下载与安装合并显示连续总进度。完成、失败或取消后自动收起。

只增加进度回报，保留原有任务、授权、上传地址与内容，以及 App 更新替换流程。

SwiftUI / AppKit 原生中文界面，保留原版全部 5 个页面与内容。采用灰绿色调、顶部标签、分层面板和有主次的柔和按钮，并支持深浅色。窗口内容区固定为 820 × 600 pt，不支持拉伸、最大化或全屏，长内容在内部滚动。只有 App 自身更新接入本仓库；驱动下载更新、诊断上传、测试通道和其他功能保持作者原有实现。

上游源码：nullmoth/1401@{state['upstream_sha'][:12]}。本仓库只发布 App，驱动由 App 从作者原有地址下载与更新。

下载 ZIP 解压后移到“应用程序”，或使用 DMG。App 为 ad-hoc 签名，未作 Apple 公证。云端测试通过不代表目标显卡的显示、应用和睡眠唤醒已验证。

原始安装器版权归 NullMoth Systems，遵循 PolyForm Noncommercial 1.0.0，限非商业用途。''')
