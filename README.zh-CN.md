<p align="center"><img src="assets/icon.png" width="128" height="128" alt="AppleCtl 图标"></p>

# AppleCtl

[English](README.md) · 简体中文 · [下载正式版](https://github.com/Jaaayden/applectl/releases/latest)

[![自动测试](https://github.com/Jaaayden/applectl/actions/workflows/test.yml/badge.svg)](https://github.com/Jaaayden/applectl/actions/workflows/test.yml)

一个本机命令行工具，统一管理 macOS 的苹果日历与提醒事项，供人和 Agent 使用。

工具通过公开 EventKit 读写与苹果应用相同的数据，默认返回 JSON。使用时无需截图、Computer Use、账号令牌或额外常驻服务；系统和 iCloud 同步由 macOS 管理。配套 [Skill](skills/apple-calendar-reminders/SKILL.md) 只调用本项目。

## 安装

需要 macOS 14+ 和 Python 3。

**预编译安装包**：从 [Releases](https://github.com/Jaaayden/applectl/releases) 下载 Apple 芯片的 `macos-arm64.tar.gz` 或 Intel 的 `macos-x86_64.tar.gz`。解压后在该目录执行：

```bash
python3 scripts/install.py
```

包内附带应用、命令行启动器、Skill、安装说明和许可证，安装时无需 Swift 编译器。同版本的 SHA256SUMS 可用来核对下载文件。

**源码安装**：另外需要 Swift 6.0+ 工具链：

```bash
git clone https://github.com/Jaaayden/applectl.git
cd applectl
python3 scripts/install.py
```

命令安装到 `~/.local/bin/applectl`，应用安装到 `~/Library/Application Support/AppleCtl/AppleCtl.app`。将 `~/.local/bin` 加入 PATH，或直接使用完整命令路径。安装器会保留无关的同名命令或应用，并为已管理的应用保留上一版备份。

应用采用临时本地签名，尚未提供 Apple Developer 签名或公证。下载版本首次运行可能需要在系统设置手动允许；也可以选择源码安装。安装器不会移除 macOS 的隔离属性。

## 首次授权

```bash
applectl auth status
applectl auth grant --all
```

在系统弹窗允许访问日历和提醒事项。只需要一种数据时，使用 `--calendar` 或 `--reminders`。已拒绝时，在“系统设置 → 隐私与安全性 → 日历/提醒事项”允许 AppleCtl。

启动器通过公开 Launch Services 启动有独立身份的后台应用；不调用私有授权归属接口。每次调用结束后退出。重新编译和签名后可能需要重新授权。

## 常见操作

```bash
applectl calendars list
applectl events list --from 2026-10-01 --to 2026-10-08 --timezone Asia/Shanghai
applectl events add --title '组会' \
  --start '2026-10-01T09:00:00+08:00' --end '2026-10-01T10:00:00+08:00' \
  --timezone Asia/Shanghai --dry-run

applectl lists list
applectl reminders list --filter today
applectl reminders add --title '准备报告' --due '2026-10-01 09:00' --dry-run
applectl reminders edit --id REMINDER_ID --due '2026-10-02 09:00' --alarm '2026-10-02 09:00'
applectl reminders complete --id REMINDER_ID
```

以上新增示例使用 `--dry-run` 预览；需要实际保存时去掉它。未指定日历或清单时使用系统默认目标；名称重复时使用完整 ID。所有操作返回 `ok`、`data` 或 `error`、`meta`；`meta.exitCode` 与退出码一致。失败和超时不能视为已经保存；超时后先回读，再决定是否重试。

日期与时间：

- 没有偏移量的时间按 `--timezone` 解释；省略时使用本机时区。建议定时日程使用带偏移量的 ISO 8601。
- 查询区间为 `[from,to)`，每次最多 366 天；默认查询从今天开始的七天，并包含与区间相交的事件。
- 全天日程的结束日期不包含在活动内：10 月 1 日的一天活动，结束设为 10 月 2 日并加 `--all-day`。
- 仅日期的待办是全天提醒；定时到期日默认创建同一时间的通知。只改到期日会保留已有闹钟，改变通知时间需要显式设置 `--alarm`。
- `--clear-alarm` 清空绝对日期闹钟，保留相对和地点闹钟。完成重复待办后，系统可能生成下一次待办。

### 重复日程

每次发生都保留在列表结果中，使用 `id` 和 `occurrenceStart` 共同定位。操作前先刷新对应日期区间。

```bash
applectl events edit --id EVENT_ID --occurrence-start '2026-10-08T09:00:00+08:00' \
  --scope this --title '调整后的组会' --dry-run
```

单次 `this`（默认）和后续 `future` 范围必须提供发生时间；整组 `all` 使用原系列 ID，不带发生时间，也不能用已经分离的实例代替系列。可用 `--expected-revision` 拒绝过期修改。部分更新保留未指定字段，显式清空另有参数。

### 删除

```bash
applectl events delete --id EVENT_ID --dry-run
applectl reminders delete --id REMINDER_ID --force
```

删除要求 `--force`；预览使用 `--dry-run`。提醒事项和容器使用完整 ID，不使用显示序号。删除日历或提醒清单会影响其中全部记录。

## 安装 Agent Skill

在源码仓库或解压后的安装包目录执行：

```bash
mkdir -p "$HOME/.agents/skills"
ln -s "$PWD/skills/apple-calendar-reminders" "$HOME/.agents/skills/apple-calendar-reminders"
```

如果已经使用 `~/.codex/skills`，改用该目录，不重复安装到两处。保留安装包或仓库目录，让软链接持续有效。安装后可以直接用自然语言让 Agent 添加活动、查询日程或管理待办。

## 验证、CI 与发版

```bash
swift test
python3 -m unittest discover -s Tests/Python
python3 scripts/live_verify.py --acknowledge-temporary-data
```

真实测试需要两项系统权限，只在独立临时日历和提醒清单中操作，结束后清理；不输出个人记录。清理失败时保留本机恢复元数据。

CI 在 Apple 芯片和 Intel 上检查版本、Swift 测试、启动器与打包边界。推送与 VERSION 一致的 `vX.Y.Z` 标签后，发布工作流先运行测试，再构建两种架构、验证签名和版本、生成 SHA256SUMS，最后发布 GitHub Release。维护者发新版时同时更新 `VERSION`、`Sources/AppleCore/ToolVersion.swift` 和 `RELEASE_NOTES.md`。 发布中断时可在 Actions 的 Release 工作流选择 Run workflow，填入已有标签；测试和构建仍使用该标签，发布步骤按 Release ID 恢复草稿，核对远端摘要后公开，拒绝覆盖已公开版本。

## 能力边界与来源

公开 EventKit 不提供原生提醒事项标签、智能清单、分区、附件或 Urgent 开关，也不提供任意邀请管理。新建重复规则支持每日/每周/每月/每年及间隔，日历可指定次数或结束日期；未修改的复杂规则会保留。

本机发现 EventKit 对 2099 年重复日程可以保存规则但返回空发生列表；下一年的重复读写已验证。未建立系统远期展开的完整边界，不能保证任意遥远年份。跨服务提供商提交也不是分布式事务，结果不明时先回读。

提醒核心改编自 [remindctl](https://github.com/openclaw/remindctl)，日历部分参考 [apple-calendar-cli](https://github.com/sichengchen/apple-calendar-cli)，并修正 [acal](https://github.com/Helmi/acal-apple-calendar-cli) 中发现的相关路径。本项目只使用公开接口。具体版本、修改和验证见 [THIRD_PARTY.md](THIRD_PARTY.md) 与 [AUDIT.md](AUDIT.md)。

MIT 许可，上游声明保留在 [licenses/](licenses/)。原创图标提供 [SVG](assets/icon.svg)、[PNG](assets/icon.png) 和 macOS ICNS。
