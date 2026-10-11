#!/usr/bin/env python3
"""Check the API against what the widget needs. Run after each backend change.

    python tools/verify-backend.py --base https://chup.tech/api/v1/ \
        --email someone@clinic.com --password ...

Exits non-zero if anything the widget depends on is missing, so it can gate CI.
Reads nothing but the queue; it never writes, so it is safe against staging.
"""
import argparse
import json
import sys
import urllib.error
import urllib.request

OK, BAD, WARN = "  OK  ", " MISS ", " WARN "


def call(url, token=None, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method="POST" if data else "GET",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            # Cloudflare fronts both hosts and 403s urllib's default agent.
            "User-Agent": "chup-widget-verify/1.0",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode()
    except urllib.error.HTTPError as e:
        body = e.read().decode()
    except Exception as e:  # noqa: BLE001
        return None, f"unreachable: {e}"
    # An expired/absent token answers with an HTML redirect, not JSON.
    if body.lstrip().startswith("<"):
        return None, "HTML redirect (not signed in?)"
    try:
        return json.loads(body), None
    except json.JSONDecodeError:
        return None, f"non-JSON: {body[:80]}"


def rows(res):
    """Both endpoints wrap a Laravel paginator; serving is a list too."""
    d = (res or {}).get("data")
    inner = d.get("data") if isinstance(d, dict) else d
    return inner if isinstance(inner, list) else []


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base", required=True, help="e.g. https://chup.tech/api/v1/")
    p.add_argument("--email", required=True)
    p.add_argument("--password", required=True)
    a = p.parse_args()
    base = a.base if a.base.endswith("/") else a.base + "/"

    failures = []

    def check(cond, label, detail="", fatal=True):
        print(f"[{OK if cond else (BAD if fatal else WARN)}] {label}"
              + (f" — {detail}" if detail and not cond else ""))
        if not cond and fatal:
            failures.append(label)

    print(f"\nBase: {base}\n")

    # --- auth -------------------------------------------------------------
    res, err = call(base + "user/auth/widget-login",
                    payload={"email": a.email, "password": a.password})
    check(res is not None, "widget-login reachable", err or "")
    if res is None:
        sys.exit(1)

    # A wrong password comes back as HTTP 200 with error:true in the body.
    check(res.get("error") is not True, "credentials accepted",
          str(res.get("message"))[:60])
    data = res.get("data") or {}
    token = data.get("api_token")
    check(bool(token), "data.api_token present",
          f"got keys {list(data)[:5]}")
    if not token:
        sys.exit(1)

    # --- queue ------------------------------------------------------------
    # widget=1 asks for called_at / started_at / limits (chup.online 577101b68).
    serving, err1 = call(base + "user/visits/serving?widget=1", token)
    visits, err2 = call(base + "user/visits?widget=1&size=50", token)
    check(serving is not None, "GET user/visits/serving", err1 or "")
    check(visits is not None, "GET user/visits", err2 or "")

    sample = (rows(serving) or []) + (rows(visits) or [])
    if not sample:
        print(f"\n[{WARN}] queue is empty — field checks need at least one visit.")
        print("        Register a test patient for today, then re-run.")
        sys.exit(1 if failures else 0)

    v = sample[0]
    print(f"\nChecking fields on visit id={v.get('id')}:\n")

    # Already present today.
    for key in ("id", "token", "sort_index", "state", "client", "arrived_at"):
        check(key in v, f"{key}", "expected on every visit")

    # The redesign's gaps.
    print()
    for key, why in (
        ("called_at", "drives GRACE + flips the button to END VISIT"),
        ("started_at", "drives the serving meter against SERVE"),
    ):
        check(key in v and v.get(key) is not None, f"{key}", why, fatal=False)

    limits = ((visits or {}).get("data") or {}).get("limits") or (visits or {}).get("limits")
    check(isinstance(limits, dict), "limits {wait,consult,grace}_minutes",
          "widget falls back to 20/15/5", fatal=False)

    # Timestamps must carry an offset or every minute figure is wrong.
    for key in ("arrived_at", "called_at", "started_at"):
        val = v.get(key)
        if isinstance(val, str):
            check(("+" in val[10:] or val.endswith("Z")), f"{key} has a UTC offset",
                  f"got {val!r} — will be read as local time", fatal=False)

    print()
    if failures:
        print(f"FAILED — {len(failures)} required item(s): {', '.join(failures)}")
        sys.exit(1)
    print("Required fields present. Items marked WARN are the redesign's gaps.")


if __name__ == "__main__":
    main()
