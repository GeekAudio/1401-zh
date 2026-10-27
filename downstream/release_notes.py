import json
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
print(f'''为本机扫描、更新检查与下载、安装和 EFI 操作、GPU 测量、USB 监测、日志与诊断任务加入原生进度条。下载按实际字节显示进度，GPU 测量按已完成阶段显示进度，无法估算的任务显示不定进度；完成、失败或取消后自动收起。原有执行、授权、上传和 App 更新替换逻辑不变。

SwiftUI / AppKit 原生中文界面，保留原版全部 5 个页面与内容。采用灰绿色调、顶部标签、分层面板和有主次的柔和按钮，并支持深浅色。窗口内容区固定为 820 × 600 pt，不支持拉伸、最大化或全屏，长内容在内部滚动。只有 App 自身更新接入本仓库；驱动下载更新、诊断上传、测试通道和其他功能保持作者原有实现。

上游源码：nullmoth/1401@{state['upstream_sha'][:12]}。本仓库只发布 App，驱动由 App 从作者原有地址下载与更新。

下载 ZIP 解压后移到“应用程序”，或使用 DMG。App 为 ad-hoc 签名，未作 Apple 公证。云端测试通过不代表目标显卡的显示、应用和睡眠唤醒已验证。

原始安装器版权归 NullMoth Systems，遵循 PolyForm Noncommercial 1.0.0，限非商业用途。''')
