---
name: apple-calendar-reminders
description: 使用统一的 applectl 命令行工具读取和管理 macOS 苹果日历、日程、提醒事项及待办清单，支持 JSON、重复日程和写入预览。用于用户要求添加活动、会议或创建、调整、完成待办；用户明确指定其他服务时遵从其指定，不用于聊天通知或定时唤醒 Agent。
---

# 苹果日历与提醒事项

使用 `applectl`，不要转到 `remindctl`、`acal` 或 Computer Use。当前项目把两种数据源合并到一个公开 EventKit 后端。命令不在 PATH 时使用 `~/.local/bin/applectl`。运行 `applectl --help` 查看当前语法。

活动、会议、讲座等使用 `events`；待办使用 `reminders`。遵从用户在当前任务中指定的应用、日期、时区、目标日历或清单，不以此技能扩大授权。

## 权限与结果

- 用 `applectl auth status` 查看日历和提醒事项权限。缺少相关权限时运行 `auth grant --calendar` 或 `--reminders`；用户需允许 macOS 系统弹窗。权限拒绝时说明系统设置路径，不重复尝试绕过授权。
- 默认输出 JSON。先检查退出状态和 `ok`，再读取 `data`。失败后不要把未写入的内容称为已添加。超时或提交结果不明时先回读目标，再决定是否重试，避免重复记录。
- 已授权且目标明确时直接执行；仅在时间、对象或操作范围存在实质歧义时澄清。用户明确要求删除时使用 `--force`，不用再索取同一授权。

## 日历

```bash
applectl calendars list
applectl events list --from 2026-10-01 --to 2026-10-02 --timezone Asia/Shanghai
applectl events add --calendar CALENDAR_ID --title '报告' \
  --start '2026-10-01T09:00:00+08:00' --end '2026-10-01T10:00:00+08:00' \
  --timezone Asia/Shanghai
```

- 默认日历来自系统；用户指定名称时先读取日历列表，名称重复使用完整 ID。只读日历不能写入。
- 使用明确的日期和时区。未给结束时间且无法从活动资料确定时询问，不擅自编造时长。时间区间为 `[from,to)`，每次最多 366 天；查询当天需把 `to` 设为次日。
- 全天事件显式使用 `--all-day` 和日期值，结束日期是活动最后一天的次日。保留用户只提供日期的含义。
- 重复事件的每次发生都在结果中。先刷新相应时间区间，用返回的 `id` 与 `occurrenceStart` 一起定位。编辑/删除默认 `--scope this`；`this`/`future` 需传 `--occurrence-start`，整组使用 `--scope all` 且不传发生时间。整组操作使用原系列 ID，不能用 detached 实例替代。
- 使用 `events get --id ID` 或带发生时间读取详情，再部分更新所需字段；可用读取的 `revision` 配合 `--expected-revision` 防止过期覆盖。只修改时间时保留备注、地点、重复规则和提醒。
- `--dry-run` 用于用户要求预览、复杂修改或删除对象的核对；普通明确的新建任务无需强制增加一轮方案确认。修改之后回读核对实际状态。

## 提醒事项

```bash
applectl lists list
applectl reminders list --filter today
applectl reminders add --title '准备报告' --list-id LIST_ID --due '2026-10-01 09:00'
applectl reminders edit --id REMINDER_ID --due '2026-10-02 09:00' --alarm '2026-10-02 09:00'
applectl reminders complete --id REMINDER_ID
```

- 未指定清单时用系统默认清单；指定清单先读取列表，用完整 ID。提醒事项也使用完整 ID，不使用列表中的显示序号。
- 仅日期的 `--due` 创建全天提醒；带时间的到期默认有同一时间的提醒。只改到期日会保留现有提醒闹钟。如果用户要求改变通知时间，显式修改 `--alarm`；保留用户设置的其他时间或地点提醒。
- `--clear-alarm` 清空绝对日期闹钟，保留相对和地点闹钟；不能据此宣称已取消所有种类的通知。重复待办完成后可能由系统生成下一次待办，不使用日历的 `--scope` 选项处理待办。
- 支持标题、备注、URL、优先级、清单移动、到期与闹钟、简单重复、完成/撤销完成。显式清空使用 `--clear-due`、`--clear-alarm`、`--clear-url`、`--no-repeat`；不把省略字段当作清空。
- `reminders list --filter overdue` 包含今天已过期的定时待办；今天的全天待办到次日才视为过期。
- 删除用 `reminders delete --id ID --force`。日历或清单删除会影响其中所有记录，必须确认用户授权覆盖整个容器。
- 不承诺原生标签、智能列表、分区、附件或 Urgent 开关；工具仅使用公开 EventKit，不读写私有数据库。

源码、安装与回归说明位于 [README.md](../../README.md) 和 [AUDIT.md](../../AUDIT.md)。升级时在此 Skill 所属仓库重新运行 `scripts/install.py`；本机签名变化后可能需要重新给予系统权限。
