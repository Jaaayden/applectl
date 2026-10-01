# 源码审查与验证

本次审查针对 [THIRD_PARTY.md](THIRD_PARTY.md) 记录的固定版本，不代表对上游最新版本的结论，也不是完整安全认证。下面的上游问题来自源码检查；没有给原日历 CLI 授权运行其危险路径，不能称为在真实个人日历中复现。

## 上游发现与处理

| 发现 | 证据与影响 | applectl 的处理 |
| --- | --- | --- |
| 重复日程可能触发重复键错误 | [acal 的事件列表](https://github.com/Helmi/acal-apple-calendar-cli/blob/0519c9680c4fa3efe8a2692966c2f893f8a5ecbf/Sources/EventKitAdapter/EventKitAdapter.swift#L180) 用 `Dictionary(uniqueKeysWithValues:)` 按 `calendarItemIdentifier` 建表。多个发生实例或重复查询边界返回相同标识时，这个初始化会触发错误。 | 按日历 ID、条目 ID、发生时间去重，保留每次发生。 |
| 外部 ID 查询会再次同步进入同一串行队列 | [acal 的 getEvent](https://github.com/Helmi/acal-apple-calendar-cli/blob/0519c9680c4fa3efe8a2692966c2f893f8a5ecbf/Sources/EventKitAdapter/EventKitAdapter.swift#L201) 在 `queue.sync` 内调用同样使用 `queue.sync` 的 `listEvents`。 | 日历操作隔离到 MainActor，不使用嵌套同步队列；当前 CLI 只接受完整条目 ID。 |
| 发生时间没有用于定位实际修改对象 | [acal 的更新和删除](https://github.com/Helmi/acal-apple-calendar-cli/blob/0519c9680c4fa3efe8a2692966c2f893f8a5ecbf/Sources/EventKitAdapter/EventKitAdapter.swift#L285) 先按 ID 获取对象，发生时间只用于结果或是否缺失的检查。Apple 明确说明按 ID 返回事件的首次发生。 | 用发生时间查询实际实例，核对系列与日历，拒绝缺失或歧义对象；重复事件的 this/future 操作必须有发生时间。 |
| 只写权限被当成读取权限 | [acal 的 ensureReadAccess](https://github.com/Helmi/acal-apple-calendar-cli/blob/0519c9680c4fa3efe8a2692966c2f893f8a5ecbf/Sources/EventKitAdapter/EventKitAdapter.swift#L382) 接受 writeOnly。读取不可用时可能返回误导性的空结果。 | 明确要求日历完整权限，拒绝把权限不足解释为空数据。 |
| 仅日期输入在负时区可能回退一天 | [acal 的 DateCodec](https://github.com/Helmi/acal-apple-calendar-cli/blob/0519c9680c4fa3efe8a2692966c2f893f8a5ecbf/Sources/AppCore/DateCodec.swift#L18) 先按 UTC 零点解析，再用目标时区提取日期字段。 | 在目标时区严格解析原日期，验证无效日期、偏移量和夏令时日期。 |
| 单字段修改没有检查最终起止顺序 | [acal 的更新](https://github.com/Helmi/acal-apple-calendar-cli/blob/0519c9680c4fa3efe8a2692966c2f893f8a5ecbf/Sources/EventKitAdapter/EventKitAdapter.swift#L285) 直接改变 start/end 后保存。 | 合并原字段后再验证 end > start。 |
| 诊断读取私有提醒事项数据库 | [remindctl doctor](https://github.com/openclaw/remindctl/blob/ea2fb1098a2de73e0b90b95543b79217c6628b87/Sources/remindctl/Commands/DoctorCommand.swift#L36) 调用 RichReadDiagnostics，后者查找私有 SQLite 数据库并运行 sqlite3。这里是读取诊断，并非发现恶意上传。 | 未引入原 CLI 或数据库诊断，只通过公开 EventKit 接口操作。 |
| 批量提醒操作可能执行一部分后失败 | [remindctl 批量操作](https://github.com/openclaw/remindctl/blob/ea2fb1098a2de73e0b90b95543b79217c6628b87/Sources/RemindCore/EventKitStore.swift#L180) 逐项查 ID 并立即提交；后续 ID 无效时，前面的操作已经完成。 | core 先验证所有 ID 和可写性，再暂存修改并统一提交；错误时 reset。CLI 当前逐个完整 ID 操作。 |
| 今天稍早到期的定时提醒不在 overdue 中 | remindctl 的 overdue 只比较当天零点。 | 定时待办与当前时间比较；全天待办仍按日期判断。 |
| 私有系统授权归属接口依赖 | [acal 的 ResponsibilityDisclaim](https://github.com/Helmi/acal-apple-calendar-cli/blob/0519c9680c4fa3efe8a2692966c2f893f8a5ecbf/Sources/App/ResponsibilityDisclaim.swift) 动态调用未公开的 responsibility_spawnattrs_setdisclaim。 | 未引入；使用本地签名应用和公开 Launch Services，并保留 macOS 的正常系统授权。 |

参考 Apple 的 [按标识查询](https://developer.apple.com/documentation/eventkit/ekeventstore/calendaritem%28withidentifier%3A%29) 与 [创建、修改日程和提醒事项](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders)。整组日程操作使用首次发生和 futureEvents；已分离的实例不能代替原系列。

## 新项目的额外检查

- 检查未知、重复、缺值及冲突参数；删除要求显式 `--force`，预览使用 `--dry-run`。
- 日历和提醒事项的部分更新保留未指定字段，显式清空另有参数；预览也验证标题和目标清单可写性。
- 区分到期日和通知时间；调整提醒到期日不会隐式抹掉地点或时间闹钟。
- 日历闹钟区分相对、绝对及地点类型，不把绝对闹钟错误显示成零分钟。
- 不保留未使用的原进程调用助手或提醒列表序号解析器。
- 结果经权限为 0700 的临时目录返回，随后清理；超时返回结果未确认，自动重试次数为零。
- 安装时保留无关命令和应用，签名后验证本地应用；项目不保存账号令牌或个人日历导出。

## 本机验证记录

环境：macOS 15.7.7 / arm64，Swift 6.1.2。自动检查于 2026-09-30 至 2026-10-01 完成。

| 检查 | 结果 |
| --- | --- |
| Swift 测试 | 29 项通过：10 项 XCTest + 19 项 Swift Testing，包含参数化输入。 |
| Python 启动器测试 | 5 项通过：结果返回、失败状态、超时不重试、错误结果、启动失败及临时结果清理。 |
| 安装与打包边界测试 | 6 项通过：同名应用和命令保护、首次失败可重试、版本与标签一致、架构拒绝、发行文件范围。 |
| 预编译包实际安装 | 本机 arm64 发行包解压后，在隔离目录完成首次安装与升级；核对图标、签名、版本、启动器和上一版备份。 |
| 工作流静态检查 | actionlint 通过；双架构实际运行结果见 GitHub Actions。 |
| Skill 格式校验 | 通过官方 skill-creator 的 quick_validate.py。 |
| 本地应用安装与签名 | 安装成功；codesign 严格验证通过。 |
| 通过系统应用启动查询权限 | 成功返回 JSON；单次查询约 0.13 秒。这不是真实日程查询的吞吐量测试。 |
| 真实日历与提醒事项读写 | 2026-10-01：23 项真实检查通过，临时容器和记录全部清理。 |

`scripts/live_verify.py` 使用独立临时日历和提醒清单进行真实读写，覆盖新增、读取、修改、预览、重复日程的单次/后续/整组范围、过期修订拒绝、全天日期、提醒闹钟、完成/撤销与删除。结束时只按本次创建的完整 ID 和名称清理容器。清理失败时保留本机恢复元数据；不把这些数据提交到仓库。

## 远期重复展开的实际限制

最初使用 2099 年数据时，EventKit 保存后的重复规则显示 count=4，但查询返回 0 个发生实例。在新的专用临时日历中，同样规则的 2027 年数据返回正确的 4 项，2099 年仍为 0；两个探测系列随容器清理。此处是本机系统接口的实际行为，不是日期字符串解析错误；尚未确定完整年份边界。真实回归因此使用本机下一年，工具不自行制造系统没有返回的发生实例。

## 范围与限制

EventKit 不承诺跨服务提供商的分布式事务；提交结果不明时应回读确认。本次检查不包括所有云账号、受管理账号、邀请、复杂重复模式或每一种系统闹钟组合。原生提醒事项标签、智能清单、分区、附件和 Urgent 不通过私有数据库补齐。重装后的本机临时签名可能需要重新授权。
