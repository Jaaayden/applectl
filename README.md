<p align="center"><img src="assets/icon.png" width="128" height="128" alt="AppleCtl icon"></p>

# AppleCtl

English · [简体中文](README.zh-CN.md) · [Download](https://github.com/Jaaayden/applectl/releases/latest)

[![Tests](https://github.com/Jaaayden/applectl/actions/workflows/test.yml/badge.svg)](https://github.com/Jaaayden/applectl/actions/workflows/test.yml)

One local command for Apple Calendar and Apple Reminders on macOS 14+.

`applectl` reads and changes the same EventKit data used by Apple's apps. It returns JSON, runs without screenshots or UI automation, and does not require an account token, daemon, MCP server, or third-party cloud service. System/iCloud synchronization remains managed by macOS.

This independent project adapts the reminder core from [openclaw/remindctl](https://github.com/openclaw/remindctl), references [sichengchen/apple-calendar-cli](https://github.com/sichengchen/apple-calendar-cli), and replaces problematic calendar paths found in [Helmi/acal](https://github.com/Helmi/acal-apple-calendar-cli). See [THIRD_PARTY.md](THIRD_PARTY.md) and [AUDIT.md](AUDIT.md).

## Install

Requires macOS 14+ and Python 3. Download the matching arm64 (Apple silicon) or x86_64 (Intel) archive from [Releases](https://github.com/Jaaayden/applectl/releases), extract it and run `python3 scripts/install.py` from the extracted directory. The archive includes the app, launcher, installer, Skill and licenses; prebuilt installation does not need Swift. Verify downloads against the included SHA256SUMS.

For source installation, also provide a Swift 6.0+ toolchain. There are no Swift package dependencies.

```bash
git clone https://github.com/Jaaayden/applectl.git
cd applectl
python3 scripts/install.py
```

The installer places the command at `~/.local/bin/applectl` and a locally signed app at `~/Library/Application Support/AppleCtl/AppleCtl.app`. Add `~/.local/bin` to your PATH if necessary, or use the full command path. Prebuilt apps use ad-hoc local signatures and are not Developer ID signed or notarized. A downloaded app may need manual approval in macOS settings; the installer preserves quarantine attributes. Source builds remain available.

Existing unrelated installations are preserved. Reinstallation retains the previous managed app as a backup.

The launcher starts this background app through Launch Services, giving macOS a public, ordinary application identity for permission handling. It uses no private responsibility-disclaim API or AppleScript. Command results are returned through a private temporary directory that is removed after each invocation. There is no persistent process or network listener.

```bash
applectl auth status
applectl auth grant --all
```

Allow the Calendar and Reminders permission prompts. You can request only one with `--calendar` or `--reminders`. If access was previously denied, allow AppleCtl in System Settings → Privacy & Security → Calendars or Reminders. TCC permissions must be granted on the Mac running the tool. A rebuilt ad-hoc-signed app may require renewed permission.

## Examples

All operations return an `ok`, `data`/`error`, `meta` envelope. `meta.exitCode` matches the command's exit status. `--json` is optional because JSON is already the default. Unknown, duplicate, missing and conflicting options are rejected.

```bash
applectl calendars list
applectl events list --from 2026-10-01 --to 2026-10-08 --timezone Asia/Shanghai
applectl events add --title 'Team meeting' \
  --start '2026-10-01T09:00:00+08:00' --end '2026-10-01T10:00:00+08:00' \
  --timezone Asia/Shanghai --dry-run

applectl lists list
applectl reminders list --filter today
applectl reminders add --title 'Prepare report' --due '2026-10-01 09:00' --dry-run
applectl reminders edit --id REMINDER_ID --due '2026-10-02 09:00' --alarm '2026-10-02 09:00'
applectl reminders complete --id REMINDER_ID
```

Dates without an offset use the requested `--timezone`, otherwise the Mac's timezone. Use ISO 8601 with an explicit offset for timed events. Date-only reminder inputs create all-day reminders; timed due dates get a notification alarm by default. Changing only a reminder due date preserves its alarms; supply `--alarm` when you also intend to move the notification.

`--clear-alarm` clears absolute reminder alarms while preserving relative and location alarms. Completing a recurring reminder may cause macOS to create the next reminder; calendar occurrence scopes do not apply to reminders.

Event query ranges are `[from,to)` and limited to 366 days per call; without dates, the next seven days are returned. Events intersecting the query interval are included. All-day event end dates are exclusive: a one-day event on October 1 ends at October 2 midnight.

### Recurring events

Every occurrence remains in list output. Its `id` and `occurrenceStart` together identify the selected instance. Fetch a fresh listing before editing a recurring event.

```bash
applectl events edit --id EVENT_ID --occurrence-start '2026-10-08T09:00:00+08:00' \
  --scope this --title 'Rescheduled meeting' --dry-run
```

Edits/deletions default to `--scope this`. `this` and `future` require an occurrence anchor for recurring events; the tool queries and locates that occurrence before applying EventKit's corresponding span. `all` uses the original series ID and rejects an occurrence anchor or detached-instance ID. `--expected-revision` can reject stale edits. A read-only calendar or ambiguous calendar name is rejected.

### Deletion and containers

Use full IDs for reminders and for deleting/renaming containers. The CLI does not accept reminder display indexes. Destructive operations require `--force`; `--dry-run` previews without writing.

```bash
applectl events delete --id EVENT_ID --dry-run
applectl reminders delete --id REMINDER_ID --force
applectl calendars create --name 'Example calendar'
applectl lists create --name 'Example list'
```

`applectl --help` lists commands and options. A timeout reports an unconfirmed result: read the target back before retrying a mutation.

## Agent skill

The included [apple-calendar-reminders Skill](skills/apple-calendar-reminders/SKILL.md) calls only this unified tool. You do not need remindctl or acal installed.

On macOS, install the Skill as a link to this checkout:

```bash
mkdir -p "$HOME/.agents/skills"
ln -s "$PWD/skills/apple-calendar-reminders" "$HOME/.agents/skills/apple-calendar-reminders"
```

For an existing `~/.codex/skills` setup, use that directory instead. Avoid installing the same Skill in both locations. Keep the checkout in place. [OpenAI's skill documentation](https://learn.chatgpt.com/docs/build-skills) describes discovery and supported directories.

## Verification

```bash
swift test
python3 -m unittest discover -s Tests/Python
python3 scripts/live_verify.py --acknowledge-temporary-data
```

Unit tests cover dates/timezones, malformed arguments, recurrence anchors, occurrence identity, overdue filtering, preservation of reminder alarms, and private result transport/error handling. Live verification creates dedicated, clearly named temporary containers, exercises real calendar/reminder operations, and cleans them up. It requires both system permissions and explicit acknowledgement of temporary writes. It prints no personal event or reminder content. GitHub CI runs only tests that do not access user data.

For authorization, launch or EventKit changes, complete local automated tests, a release build and installation, first-authorization checks and live verification in temporary containers before pushing and releasing. Tests with existing permissions do not replace first-authorization checks.

## Limits

EventKit does not expose native Reminders tags, smart lists, sections, image/file attachments or the private Urgent toggle. It also does not provide arbitrary calendar invitation management. Existing complex recurrence rules are preserved unless explicitly replaced, but creation accepts only daily/weekly/monthly/yearly intervals with a count or end date. Alarm creation supports relative calendar alarms and absolute reminder alarms. No private database access is used.

On this Mac, EventKit accepted a 2099 recurring series but returned no occurrences; next-year recurrence operations were verified. Arbitrarily distant recurrence expansion is not guaranteed.

Batch reminder operations preflight IDs and permissions and then commit deferred changes together. EventKit does not promise a distributed transaction across calendar providers; if commit fails, read back before retrying.

## CI and releases

CI runs Swift, launcher and packaging tests on both Apple silicon and Intel. Tags matching `VERSION` trigger tests, native builds, app signature/version verification and SHA256SUMS generation before a GitHub Release is published. Update `VERSION`, `Sources/AppleCore/ToolVersion.swift` and `RELEASE_NOTES.md` together before tagging a new release. See [.github/workflows/release.yml](.github/workflows/release.yml). To recover an interrupted draft, manually run the Release workflow with the existing tag. Tests and builds use that tag; publication resumes the draft by release ID, verifies remote asset digests and refuses to overwrite a published release.

Original icon source: [SVG](assets/icon.svg), [PNG](assets/icon.png) and macOS ICNS.

## License

MIT, with retained third-party notices in [licenses/](licenses/).
