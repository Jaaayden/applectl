# Upstream provenance

| Project | Reviewed version / commit | Use |
| --- | --- | --- |
| [openclaw/remindctl](https://github.com/openclaw/remindctl) | v0.3.8, ea2fb1098a2de73e0b90b95543b79217c6628b87 | Adapted `Sources/RemindCore`; retained focused date, alarm and list-resolver tests. |
| [sichengchen/apple-calendar-cli](https://github.com/sichengchen/apple-calendar-cli) | v0.1.1, 941c5ba43cd9170d72d5fe7d05c00574964d49e3 | Referenced the public EventKit calendar service and serialization approach; calendar implementation and command routing rewritten here. The upstream main-branch MIT notice is retained. |
| [Helmi/acal-apple-calendar-cli](https://github.com/Helmi/acal-apple-calendar-cli) | v0.4.0, 0519c9680c4fa3efe8a2692966c2f893f8a5ecbf | Reviewed command structure and safety mechanisms; implemented corrections without retaining its CLI, MCP server, dispatch queue or private TCC-disclaim code. |

All are independent community projects. This project is not affiliated with Apple or those maintainers. Apple trademarks remain their owners' property. Complete MIT notices are retained in `licenses/`.

Changes to the adapted reminder core include applectl permission messages, validation of writable targets/nonempty titles, deferred batch commits with preflight, and correct overdue handling for timed reminders earlier on the current day. The original private-database diagnostic CLI and its process invocation were not imported.
