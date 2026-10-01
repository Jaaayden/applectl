首次正式发布 AppleCtl，统一通过公开 EventKit 操作苹果日历与提醒事项。

- 日历与待办共用一个 CLI 和配套 Agent Skill，默认 JSON 输出。
- 支持新增、查询、部分修改、预览与删除，以及重复日程的单次、后续和整组范围。
- 提供原创图标、英文与中文 README。
- 自动检查覆盖 Apple 芯片和 Intel；发布包包含应用、启动器、安装脚本、Skill 和许可证。
- 预编译包只需要 macOS 14+ 和 Python 3；从源码编译另外需要 Swift 6.0+。

安装：下载与你的运行架构对应的 tar.gz，解压后进入文件夹，执行 `python3 scripts/install.py`，再用 `applectl auth grant --all` 授予日历和提醒事项权限。SHA256SUMS 可用于校验下载内容。

预编译应用使用临时本地签名，尚未提供 Apple Developer 签名或公证。权限和 iCloud 同步由 macOS 管理。

[中文使用说明](https://github.com/Jaaayden/applectl/blob/main/README.zh-CN.md) · [审查与验证](https://github.com/Jaaayden/applectl/blob/main/AUDIT.md)
