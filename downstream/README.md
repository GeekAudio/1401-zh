# 1401 中文版

1401 的 macOS 原生中文分支，由 GeekAudio 维护。界面使用 SwiftUI 与 AppKit，安装、EFI 校验、USB 映射及硬件探测沿用上游实现。

下载：[正式 Release](https://github.com/GeekAudio/1401-zh/releases/latest) · 反馈：[GitHub Issues](https://github.com/GeekAudio/1401-zh/issues) · 上游：[nullmoth/1401](https://github.com/nullmoth/1401)

## 使用

解压 `1401-Mac-*.zip`，将“1401 中文版.app”放到“应用程序”。需要 Intel / x86_64、macOS 15 或 26，以及受支持的 NVIDIA 显卡。保持 OpenCore 启动盘连接，依次下载驱动、预览更改、核对记录、安装并重启。安装会备份配置。驱动包由本仓库 Release 镜像，校验上游固定的 SHA-256。

App 更新检查、驱动下载、问题反馈均指向本仓库。App 更新同时验证 SHA-256、独立 Ed25519 签名、Bundle ID 和版本。诊断先在本机脱敏，可预览、编辑并另存，再自行附加到 GitHub；本分支不启用上游自动上传与开机遥测。

这是非商业的社区修改版，与上游官方发行版分开维护。原作者及第三方的版权与许可证保留于 [LICENSE](LICENSE) 和 [NOTICE.md](NOTICE.md)。App 图标采用本分支绘制的芯片图形，不使用上游品牌图标。

## 上游同步、构建与发布

GitHub Actions 每 6 小时检查上游 `nullmoth/1401` 主分支及驱动正式 Release，也可在 Actions 手动运行“同步上游并发布 macOS 中文版”。有变化时同步完整源码，重新应用 `downstream/` 中文原生界面与接口配置，在 macOS 云端编译，运行测试并发布正式 Release。上游改动使补丁锚点、翻译覆盖、测试或构建不兼容时流程失败，旧版 Release 保留。

每次发布包含 App ZIP、DMG、独立签名、SHA256SUMS.txt、上游驱动原包与构建来源记录。驱动镜像必须与上游公开校验和和源码内固定哈希一致。App 采用 `上游版本.构建号`，与驱动版本分别比较。无需手动合并中文分支，也不依赖另一个 Actions 流程被推送事件再次触发。

首次配置需要仓库 Secret `RELEASE_SIGNING_KEY`，值为 Ed25519 原始 32 字节私钥的 Base64；对应公钥保存在 `downstream/release-public-key.txt` 并编入 App。私钥不可提交到仓库。若使用 Developer ID，可另行添加签名与公证；当前产物为 ad-hoc 签名，未作 Apple 公证。

```sh
python3 downstream/apply.py --source-ref upstream/main --build 1
bash mac/build.sh ../dist
python3 downstream/check.py
python3 -m unittest discover -s tests -t . -p 'test_*.py'
```

`downstream/apply.py` 从明确的上游提交重建改造，支持重复执行。`downstream/state.json` 记录当前源码提交、驱动版本、App 版本和构建号。CI 的编译与界面检查不能证明某块显卡在真实硬件上可启动、显示或完成睡眠唤醒。
