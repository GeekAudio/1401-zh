import json
import pathlib
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
print(f'''SwiftUI / AppKit 原生中文界面，保留原版全部 5 个页面与内容，只翻译、不增删。窗口宽度 920，高度随内容收紧，统一字号、行距和控件间距。只有 App 自身更新接入本仓库；驱动下载更新、诊断上传、测试通道和其他功能保持作者原有实现。

上游源码：nullmoth/1401@{state['upstream_sha'][:12]}；内置驱动固定版本：{state['driver_version']}；最新驱动镜像：{state.get('driver_release_tag', 'v' + state['driver_version'])}。

下载 ZIP 解压后移到“应用程序”，或使用 DMG。App 为 ad-hoc 签名，未作 Apple 公证。云端测试通过不代表目标显卡的显示、应用和睡眠唤醒已验证。

原始安装器版权归 NullMoth Systems，遵循 PolyForm Noncommercial 1.0.0，限非商业用途。''')
