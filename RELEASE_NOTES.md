修复全天事件在 Mac 时区与 `--timezone` 不一致时可能差一天的问题，并让编辑命令的检查与帮助更可靠。

- 全天事件现在是不带时区的日期：无论 Mac 在哪个时区、传什么 `--timezone`，都按请求的日历日存储。日期型 `--end` 仍表示最后一天的次日（开区间），返回的 `end` 为最后一天的 23:59:59。
- 创建和编辑事件后重新读取再返回，响应与之后的 `events get` / `events list` 一致。
- `events edit` / `reminders edit` 通过解析后的结构判断是否提供了更新字段，不再维护手写的选项名列表。
- `applectl <group> --help` 以 JSON 返回该命令组的用法。
- `--expected-revision` 用于没有修改时间的事件时，返回 `revision_unavailable`，不再误报冲突。
- 内部：`Runner` 拆分为 Runner / RunnerEvents / RunnerReminders，行为不变；新增相关测试和全天事件结束日期的真实读写检查。

安装：下载与你的运行架构对应的 tar.gz，解压后进入文件夹，执行 `python3 scripts/install.py`，再用 `applectl auth grant --all` 授予日历和提醒事项权限。需要 macOS 14+ 和 Python 3。

预编译应用使用临时本地签名，尚未提供 Apple Developer 签名或公证。重新安装后的系统授权弹窗需要手动允许。

[中文使用说明](https://github.com/Jaaayden/applectl/blob/main/README.zh-CN.md) · [审查与验证](https://github.com/Jaaayden/applectl/blob/main/AUDIT.md)
