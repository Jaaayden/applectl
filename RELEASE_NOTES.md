修复首次系统授权可能导致应用崩溃的问题，建议使用本版本替代 v0.1.0。

- 日历与提醒事项统一使用明确可跨线程的授权结果回调，避免 Swift 6 把系统后台回调当成调用者的 actor。
- 新增主 actor、其他 actor、拒绝和错误四项授权回归测试；自动检查共 50 项。
- 保留原创图标、英文与中文 README、统一 CLI、Agent Skill、重复日程范围和写入预览。
- 发布流程支持按 Release ID 恢复草稿，核对远端文件大小与 SHA256 后公开；已公开版本不覆盖。
- 提供 Apple 芯片与 Intel 原生安装包，以及 SHA256SUMS。

安装：下载与你的运行架构对应的 tar.gz，解压后进入文件夹，执行 `python3 scripts/install.py`，再用 `applectl auth grant --all` 授予日历和提醒事项权限。需要 macOS 14+ 和 Python 3。

预编译应用使用临时本地签名，尚未提供 Apple Developer 签名或公证。重新安装后的系统授权弹窗需要手动允许。

[中文使用说明](https://github.com/Jaaayden/applectl/blob/main/README.zh-CN.md) · [审查与验证](https://github.com/Jaaayden/applectl/blob/main/AUDIT.md)
