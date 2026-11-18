#!/usr/bin/python3 -I
"""Test sessions for Chatterbox Dev, so the Desk and the lists have something to show.

  scripts/seed-dev.py          write the sessions, restart Dev's service, then make the tasks
                               and Show on the Desk through Dev's own Desk
  scripts/seed-dev.py --remove take them out again (same restart)

Only ever touches Chatterbox Dev's data (~/Library/Application Support/Chatterbox Dev), never
the real app's. Each session has a fixed id, so running it again replaces them in place.

What it makes (the Desk's cases, plans/front-desk.md):
  Pan Am Jerseys        a task, its reply asks                  -> Needs you
    its sidequest       its reply asks                          -> a row in Pan Am's card (a sidequest's
                                                                   answer goes back to its parent)
  Deploy the site       no task, asks, Show on the Desk         -> Needs you
  Banner sizes          no task, asks                           -> not on the Desk (switch it on)
  Ship Dogear           no task, a reply that asks              -> not on the Desk
  Spring flyers         a task, finished                        -> Review
  Kite Shop notes       no task, finished                       -> lists only
"""
import datetime, json, os, socket, subprocess, sys, time, uuid

DEV = os.path.expanduser("~/Library/Application Support/Chatterbox Dev")
CONVERSATIONS = os.path.join(DEV, "Conversations")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMESPACE = uuid.UUID("6f1d3c52-1e0a-4b7e-9a51-5eed0dee0001")


def sid(name):
    return str(uuid.uuid5(NAMESPACE, name)).upper()


def stamp(minutes_ago):
    t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=minutes_ago)
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def item(kind, text, minutes_ago, **extra):
    # Every field a session's items can't do without (their decoder requires them).
    return {"id": str(uuid.uuid4()).upper(), "kind": kind, "text": text, "timestamp": stamp(minutes_ago),
            "phase": "final", "planSteps": [], "steered": False, "toolState": "done", **extra}


def user(text, m):
    return item("user", text, m, agent="claude", toolState="running")


def reply(text, m):
    return item("assistant", text, m)


# Pending approvals and questions expire when the service starts (no agent is left to answer
# them), so what waits on Shelby here is replies that ask: the Desk counts those too.
SESSIONS = [
    ("Pan Am Jerseys", 12, [
        user("Lay out the jersey mockups for the federation review.", 15),
        reply("All four jerseys are laid out: home, away, training and warm-up.\n\n**Shall I export them as PDFs for the review?**", 12)], {}),
    ("Sidequest · Check jersey sizes", 9, [
        user("Check the size chart against the supplier's sheet.", 10),
        reply("The supplier's sheet runs half a size small in the chest.\n\n**Do you want me to use the 2026 chart and adjust the chest by half a size?**", 9)],
     {"sidequestOf": sid("Pan Am Jerseys"), "sidechatOf": sid("Pan Am Jerseys"),
      "sidequestTask": "Check the size chart against the supplier's sheet", "activeBackend": "codex"}),
    ("Deploy the site", 20, [
        user("Get the new cache rules ready.", 22),
        reply("The cache rules are ready and tested on staging.\n\n**Want me to deploy them to production?**", 20)], {}),
    ("Banner sizes", 30, [
        user("Make the event banners.", 33),
        reply("I've drafted two layouts.\n\n**Which size should I use: 1920 by 600, or 1200 by 400?**", 30)], {}),
    ("Ship Dogear", 45, [
        user("Get the build ready.", 50),
        reply("Done: the build passes and the release notes are written.\n\n**Want me to upload it to TestFlight?**", 45)], {}),
    ("Spring flyers", 60, [
        user("Make the spring flyers.", 70),
        reply("All done. The three flyers are in the folder, print-ready at 300 dpi.", 60)], {}),
    ("Kite Shop notes", 90, [
        user("Summarise the kite shop meeting.", 95),
        reply("Here's the summary: launch in May, three wholesale partners, a pop-up in April.", 90)], {}),
]
TASKS = {"Pan Am Jerseys": "Export the Pan Am jersey mockups", "Spring flyers": "Spring flyers for the club"}
FOLLOW = ["Deploy the site"]


def record(title, minutes_ago, items, extra):
    r = {"id": sid(title), "title": title, "createdAt": stamp(minutes_ago + 30), "updatedAt": stamp(minutes_ago),
         "items": items, "activeBackend": "claude", "model": "sonnet", "effort": "", "personality": "friendly", "claudeMode": "default",
         "turnDates": [stamp(minutes_ago)], "turnCompletions": []}
    r.update(extra)
    return r


def service():
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(20)
    s.connect(os.path.join(DEV, "daemon.sock"))
    f = s.makefile("rwb")

    def request(op, body):
        rid = str(uuid.uuid4())
        f.write((json.dumps({"version": 1, "id": rid, "operation": op, "body": body}) + "\n").encode())
        f.flush()
        while True:
            r = json.loads(f.readline())
            if r.get("id") == rid:
                return r
    request("hello", {"role": "agent"})
    return request


def restart():
    subprocess.run([os.path.join(ROOT, "scripts/restart-service.sh"), "--dev", "--now"], check=True)
    for _ in range(60):
        time.sleep(1)
        try:
            ids = {c["record"]["id"].upper() for c in (service()("list", {"summaryOnly": True}).get("result") or [])}
            return ids
        except (OSError, ValueError):
            continue
    sys.exit("seed-dev: Dev's service didn't come back.")


def seed_desk(remove):
    """The tasks and Show on the Desk, written into Dev's desk.json just before the restart (the
    service takes Desk changes only from the app, so an agent can't make them through it)."""
    path = os.path.join(DEV, "desk.json")
    desk = json.load(open(path)) if os.path.exists(path) else {"revision": 1, "requests": []}
    ours = {sid("task " + t) for t in TASKS}
    tasks = [t for t in desk.get("tasks") or [] if t.get("id", "").upper() not in ours]
    followed = [c for c in desk.get("followed") or [] if c.upper() not in {sid(t) for t in FOLLOW}]
    if not remove:
        for title, text in TASKS.items():
            tasks.insert(0, {"id": sid("task " + title), "text": text, "source": "you", "createdAt": stamp(120),
                             "chatID": sid(title), "linkedAt": stamp(120)})
        followed += [sid(t) for t in FOLLOW]
    desk["tasks"], desk["followed"] = tasks, followed
    desk["revision"] = desk.get("revision", 1) + 1
    with open(path, "w") as out:
        json.dump(desk, out, indent=1)


def main():
    if not os.path.isdir(CONVERSATIONS):
        sys.exit("seed-dev: no Chatterbox Dev data yet; run scripts/install-dev.sh first.")
    remove = "--remove" in sys.argv
    for title, minutes, items, extra in SESSIONS:
        path = os.path.join(CONVERSATIONS, sid(title) + ".json")
        if remove:
            if os.path.exists(path):
                os.remove(path)
        else:
            with open(path, "w") as out:
                json.dump(record(title, minutes, items, extra), out, indent=1)
    seed_desk(remove)
    listed = restart()
    if remove:
        print("Removed the test sessions from Chatterbox Dev.")
        return
    missing = [t for t, *_ in SESSIONS if sid(t) not in listed]
    if missing:
        sys.exit("seed-dev: Dev didn't load: " + ", ".join(missing))
    request = service()
    desk = request("desk", {"action": "get"}).get("result") or {}
    names = {sid(t): t for t, *_ in SESSIONS}
    print(f"Seeded {len(SESSIONS)} sessions in Chatterbox Dev.")
    for column in ("needsYou", "working", "ready"):
        shown = [names.get((i.get("chatID") or i.get("id") or "").upper(), i.get("title")) for i in desk.get(column) or []]
        print(f"  {column}: {', '.join(shown) or '(none)'}")


if __name__ == "__main__":
    main()
