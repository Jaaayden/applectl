让命令行对 agent 更友好，并补充重复事件拆分后的使用提醒。

- 选项可写成 `--key value` 或 `--key=value`。
- 只写命令组（如 `applectl events`）时返回该组的用法；`applectl <组> --help` 继续返回该组用法。
- 失败结果新增 `error.hint`，对缺权限、需要 `--force`、需要刷新 `occurrenceStart`、版本冲突、日期格式等常见错误给出下一步。
- 启动器等待时间可用环境变量 `APPLECTL_TIMEOUT_SECONDS`（1–3600）调整，默认仍为 120 秒（`auth grant` 为 600 秒）；超时后仍须先回读再决定是否重试。
- Skill 与 README 补充：用 `--scope future` 拆开的系列要分别用各自的 ID 编辑，不要再对原系列用 `--scope all` 改日期。
- 新增 8 项自动测试；24 项真实读写检查全部通过。

安装：下载与你的运行架构对应的 tar.gz，解压后进入文件夹，执行 `python3 scripts/install.py`，再用 `applectl auth grant --all` 授予日历和提醒事项权限。需要 macOS 14+ 和 Python 3。

预编译应用使用临时本地签名，尚未提供 Apple Developer 签名或公证。重新安装后的系统授权弹窗需要手动允许。

[中文使用说明](https://github.com/Jaaayden/applectl/blob/main/README.zh-CN.md) · [审查与验证](https://github.com/Jaaayden/applectl/blob/main/AUDIT.md)
