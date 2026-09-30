#!/usr/bin/env python3
"""Verify real EventKit operations exclusively inside this run's temporary containers."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--acknowledge-temporary-data", action="store_true", required=True)
    parser.add_argument("--command", default=str(Path.home() / ".local/bin/applectl"))
    args = parser.parse_args()
    marker = "[applectl validation] " + uuid.uuid4().hex[:8]
    journal_dir = Path(tempfile.mkdtemp(prefix="applectl-verify-"))
    journal = journal_dir / "resources.json"
    resources = {"marker": marker, "calendar": None, "lists": []}
    passed = []

    def persist():
        journal.write_text(json.dumps(resources))
        journal.chmod(0o600)

    def call(*command, expect_error=False):
        process = subprocess.run([args.command, *command], capture_output=True, text=True, timeout=130)
        try:
            result = json.loads(process.stdout)
        except ValueError as error:
            raise RuntimeError("Command did not return JSON: " + " ".join(command[:2])) from error
        if expect_error:
            assert process.returncode != 0 and result.get("ok") is False, "Unsafe command was not rejected"
            return result
        if process.returncode or result.get("ok") is not True:
            raise RuntimeError(result.get("error", {}).get("message", "Command failed"))
        return result["data"]

    def check(name, condition):
        if not condition:
            raise AssertionError(name)
        passed.append(name)
        print("PASS " + name, flush=True)

    def event_list():
        return call("events", "list", "--calendar", resources["calendar"], "--from", "2099-10-01", "--to", "2099-12-01", "--timezone", "Asia/Shanghai")

    persist()
    try:
        status = call("auth", "status")
        if status.get("calendar") != "full-access" or status.get("reminders") != "full-access":
            raise RuntimeError("Both permissions are required. Run applectl auth grant --all first.")
        container = call("calendars", "create", "--name", marker)
        resources["calendar"] = container["id"]
        persist()
        container = call("lists", "create", "--name", marker)
        resources["lists"].append(container["id"])
        persist()
        calendar_id, list_id = resources["calendar"], resources["lists"][0]
        check("temporary writable containers", bool(calendar_id and list_id))

        event = call("events", "add", "--calendar", calendar_id, "--title", marker + " event",
                     "--start", "2099-10-01T09:00:00+08:00", "--end", "2099-10-01T10:00:00+08:00",
                     "--timezone", "Asia/Shanghai", "--notes", "Preserve this note", "--location", "Test location")
        fetched = call("events", "get", "--id", event["id"])
        check("calendar create and read", fetched["title"] == event["title"] and fetched["start"].startswith("2099-10-01T09:00"))
        call("events", "edit", "--id", event["id"], "--title", "unsaved", "--dry-run")
        check("calendar dry-run does not write", call("events", "get", "--id", event["id"])["title"] == event["title"])
        updated = call("events", "edit", "--id", event["id"], "--title", marker + " edited",
                       "--start", "2099-10-01T11:00:00+08:00", "--end", "2099-10-01T12:00:00+08:00")
        check("calendar edit preserves unrelated fields", updated["notes"] == "Preserve this note" and updated["location"] == "Test location")
        conflict = call("events", "edit", "--id", event["id"], "--title", "Stale edit", "--expected-revision", "stale", expect_error=True)
        check("stale calendar revision is rejected", conflict["error"]["code"] == "conflict" and
              call("events", "get", "--id", event["id"])["title"] == updated["title"])
        call("events", "add", "--calendar", calendar_id, "--title", "Invalid", "--start", "2099-10-01", "--end", "2099-09-30", expect_error=True)
        call("events", "delete", "--id", event["id"], expect_error=True)
        check("calendar invalid ranges and unconfirmed deletes rejected", len(event_list()) == 1)
        call("events", "delete", "--id", event["id"], "--force")
        check("calendar delete", event_list() == [])

        recurring = call("events", "add", "--calendar", calendar_id, "--title", marker + " daily",
                         "--start", "2099-10-11T09:00:00+08:00", "--end", "2099-10-11T09:30:00+08:00",
                         "--timezone", "Asia/Shanghai", "--repeat", "daily", "--count", "4")
        occurrences = event_list()
        check("all recurring occurrences are retained", len(occurrences) == 4 and len({item["start"] for item in occurrences}) == 4)
        call("events", "edit", "--id", recurring["id"], "--title", "Unsafe", expect_error=True)
        check("recurring mutation without anchor rejected", all(item["title"] == recurring["title"] for item in event_list()))
        second = occurrences[1]
        call("events", "edit", "--id", second["id"], "--occurrence-start", second["occurrenceStart"],
             "--scope", "this", "--title", marker + " only second")
        occurrences = event_list()
        check("single occurrence edit targets requested date", len(occurrences) == 4 and
              occurrences[0]["title"] == recurring["title"] and occurrences[1]["title"] == marker + " only second" and
              occurrences[2]["title"] == recurring["title"])
        third = occurrences[2]
        call("events", "edit", "--id", third["id"], "--occurrence-start", third["occurrenceStart"],
             "--scope", "future", "--title", marker + " future")
        occurrences = event_list()
        check("future occurrence edit preserves earlier dates", len(occurrences) == 4 and
              occurrences[0]["title"] == recurring["title"] and occurrences[1]["title"] == marker + " only second" and
              all(item["title"] == marker + " future" for item in occurrences[2:]))
        third = occurrences[2]
        call("events", "delete", "--id", third["id"], "--occurrence-start", third["occurrenceStart"], "--scope", "future", "--force")
        check("future occurrence deletion preserves earlier dates", len(event_list()) == 2)
        remaining = event_list()
        for item in remaining:
            # The second instance can be detached from the truncated original series.
            call("events", "delete", "--id", item["id"], "--occurrence-start", item["occurrenceStart"], "--scope", "this", "--force")
        check("single occurrence deletion", event_list() == [])

        whole_series = call("events", "add", "--calendar", calendar_id, "--title", marker + " whole series",
                            "--start", "2099-10-21T09:00:00+08:00", "--end", "2099-10-21T09:30:00+08:00",
                            "--timezone", "Asia/Shanghai", "--repeat", "daily", "--count", "3")
        call("events", "edit", "--id", whole_series["id"], "--scope", "all", "--title", marker + " all edited")
        check("whole-series edit", len(event_list()) == 3 and all(item["title"] == marker + " all edited" for item in event_list()))
        series_id = event_list()[0]["id"]
        call("events", "delete", "--id", series_id, "--scope", "all", "--force")
        check("whole-series delete", event_list() == [])

        allday = call("events", "add", "--calendar", calendar_id, "--title", marker + " all day",
                      "--start", "2099-11-01", "--end", "2099-11-02", "--all-day", "--timezone", "America/New_York")
        check("all-day date in negative timezone", allday["allDay"] and allday["start"].startswith("2099-11-01"))
        call("events", "delete", "--id", allday["id"], "--force")

        reminder = call("reminders", "add", "--list-id", list_id, "--title", marker + " reminder", "--due", "2099-10-01 09:00",
                        "--timezone", "Asia/Shanghai", "--notes", "Keep this note", "--priority", "high")
        fetched = call("reminders", "get", "--id", reminder["id"])
        check("reminder create and due alarm", fetched["title"] == reminder["title"] and bool(fetched.get("alarmDate")))
        call("reminders", "edit", "--id", reminder["id"], "--title", " ", "--dry-run", expect_error=True)
        check("invalid reminder preview rejected", call("reminders", "get", "--id", reminder["id"])["title"] == reminder["title"])
        preview = call("reminders", "edit", "--id", reminder["id"], "--title", "unsaved", "--dry-run")
        check("reminder dry-run previews changes without writing", preview["changes"]["title"] == "unsaved" and
              call("reminders", "get", "--id", reminder["id"])["title"] == reminder["title"])
        updated = call("reminders", "edit", "--id", reminder["id"], "--due", "2099-10-02 09:00", "--alarm", "2099-10-02 09:00")
        check("reminder reschedule and unrelated fields", updated["dueDate"].startswith("2099-10-02") and
              updated["alarmDate"].startswith("2099-10-02") and updated["notes"] == "Keep this note" and updated["priority"] == "high")
        call("reminders", "complete", "--id", reminder["id"])
        check("reminder completion", call("reminders", "get", "--id", reminder["id"])["isCompleted"] is True)
        call("reminders", "edit", "--id", reminder["id"], "--incomplete", "--clear-due", "--clear-alarm")
        updated = call("reminders", "get", "--id", reminder["id"])
        check("reminder reopen and explicit clears", updated["isCompleted"] is False and not updated.get("dueDate") and not updated.get("alarmDate"))
        call("reminders", "delete", "--id", reminder["id"], "--force")
        check("reminder delete", call("reminders", "list", "--list-id", list_id, "--filter", "all") == [])
        print(f"Verified {len(passed)} live checks.", flush=True)
    finally:
        cleanup_errors = []
        for list_id in resources["lists"]:
            try:
                entries = call("lists", "list")
                match = next((item for item in entries if item["id"] == list_id), None)
                if match is not None:
                    if match["title"] != marker:
                        raise RuntimeError("Temporary list was renamed externally; preserved it.")
                    call("lists", "delete", "--id", list_id, "--force")
            except Exception as error:
                cleanup_errors.append(str(error))
        if resources["calendar"]:
            try:
                entries = call("calendars", "list")
                match = next((item for item in entries if item["id"] == resources["calendar"]), None)
                if match is not None:
                    if match["title"] != marker:
                        raise RuntimeError("Temporary calendar was renamed externally; preserved it.")
                    call("calendars", "delete", "--id", resources["calendar"], "--force")
            except Exception as error:
                cleanup_errors.append(str(error))
        if cleanup_errors:
            print("Cleanup needs attention; recovery metadata: " + str(journal), flush=True)
            raise RuntimeError("; ".join(cleanup_errors))
        shutil.rmtree(journal_dir)
        print("Temporary containers and records cleaned up.", flush=True)


if __name__ == "__main__":
    main()
