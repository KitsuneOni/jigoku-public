#!/usr/bin/env python3
"""Push reminders for upcoming Radicale events to ntfy."""
import base64, datetime as dt, os, re, sys, urllib.request
from zoneinfo import ZoneInfo

BASE  = os.environ.get("RADICALE_URL", "http://127.0.0.1:5232")
NTFY  = os.environ.get("NTFY_URL", "http://192.168.1.11:8080/jigoku-alerts")
STATE = "/var/lib/calendar-reminders/sent"
LOCAL = ZoneInfo(os.environ.get("TZ", "Pacific/Auckland"))
USER, PASS, TOKEN = os.environ["RADICALE_USER"], os.environ["RADICALE_PASS"], os.environ["NTFY_TOKEN"]

LEADS = {"assignment": 10080, "deadline": 10080, "uni": 60, "class": 60, "lecture": 60}
DEFAULT_LEAD = 30
PROPFIND = b'<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:displayname/></d:prop></d:propfind>'


def req(path, method="PROPFIND", depth="1"):
    r = urllib.request.Request(BASE + path, method=method,
                               data=PROPFIND if method == "PROPFIND" else None)
    r.add_header("Authorization", "Basic " + base64.b64encode(f"{USER}:{PASS}".encode()).decode())
    r.add_header("Depth", depth)
    if method == "PROPFIND":
        r.add_header("Content-Type", "application/xml")
    return urllib.request.urlopen(r, timeout=15).read().decode(errors="replace")


def notify(title, body):
    r = urllib.request.Request(NTFY, data=body.encode(), method="POST")
    r.add_header("Authorization", "Bearer " + TOKEN)
    r.add_header("Title", title)
    try:
        urllib.request.urlopen(r, timeout=10)
    except Exception as e:
        print(f"warn: notify failed for {title!r}: {e}", file=sys.stderr)


def parse_start(ics):
    """Return an aware datetime for DTSTART, handling TZID, UTC and all-day."""
    m = re.search(r"^DTSTART;TZID=([^:]+):(\d{8}T\d{6})", ics, re.M)
    if m:
        try:
            tz = ZoneInfo(m.group(1))
        except Exception:
            tz = LOCAL
        return dt.datetime.strptime(m.group(2), "%Y%m%dT%H%M%S").replace(tzinfo=tz)
    m = re.search(r"^DTSTART[^:]*:(\d{8}T\d{6})Z", ics, re.M)
    if m:
        return dt.datetime.strptime(m.group(1), "%Y%m%dT%H%M%S").replace(tzinfo=dt.timezone.utc)
    m = re.search(r"^DTSTART;VALUE=DATE:(\d{8})", ics, re.M)
    if m:
        return dt.datetime.strptime(m.group(1), "%Y%m%d").replace(tzinfo=LOCAL)
    return None


def main():
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    open(STATE, "a").close()
    sent = set(open(STATE).read().split())
    now = dt.datetime.now(dt.timezone.utc)
    fired = []

    try:
        index = req(f"/{USER}/")
    except Exception as e:
        print(f"warn: could not list collections: {e}", file=sys.stderr)
        return 0

    for coll in set(re.findall(rf"href>/{USER}/([^/<]+)/</", index)):
        try:
            listing = req(f"/{USER}/{coll}/")
        except Exception:
            continue
        name = re.search(r"<[^>]*displayname>([^<]+)<", listing)
        label = name.group(1) if name else coll
        lead = next((m for f, m in LEADS.items() if f in label.lower()), DEFAULT_LEAD)

        for href in set(re.findall(rf"href>/{USER}/{re.escape(coll)}/([^<]+\.ics)</", listing)):
            try:
                ics = req(f"/{USER}/{coll}/{href}", method="GET")
            except Exception:
                continue
            start = parse_start(ics)
            if not start:
                continue
            key = f"{coll}:{href}:{start.isoformat()}"
            if key in sent:
                continue
            mins = (start - now).total_seconds() / 60
            if 0 < mins <= lead:
                s = re.search(r"^SUMMARY:(.+)$", ics, re.M)
                title = s.group(1).strip() if s else "(untitled event)"
                h, m = divmod(int(mins), 60)
                notify(title, f"{start.astimezone(LOCAL):%a %d %b, %H:%M} — in "
                              f"{f'{h}h {m}m' if h else f'{m}m'} ({label})")
                fired.append(key)

    if fired:
        open(STATE, "a").write("\n".join(fired) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
