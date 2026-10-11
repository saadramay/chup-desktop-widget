#!/usr/bin/env python3
"""Exercise the widget's four actions end to end against STAGING.

    python tools/e2e-actions.py --email staff@clinic --password ... \
        --visit-a 123 --visit-b 456 --yes

Visit A goes Alert -> Start -> End Visit. Visit B goes Alert -> No-Show (the
first real call of that route). Both must be test patients waiting in the
signed-in staff member's queue today. This WRITES queue state and Alert sends a
WhatsApp, so use test patients whose phone is yours. Refuses production.
"""
import argparse
import json
import sys
import urllib.error
import urllib.request

STATES = {1: "IN_QUEUE", 2: "ALERTED", 3: "ARRIVED", 4: "SERVING", 5: "SERVED",
          6: "DELAYED", 7: "CANCELED", 8: "NO_SHOW", 9: "EARLY_ARRIVED",
          10: "MOVED", 11: "ON_HOLD"}


def call(base, path, method="GET", token=None, payload=None, query=""):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        base + path + query, data=data, method=method,
        headers={"Accept": "application/json", "Content-Type": "application/json",
                 # Cloudflare 403s urllib's default agent.
                 "User-Agent": "chup-widget-e2e/1.0",
                 **({"Authorization": f"Bearer {token}"} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            status, body = r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        status, body = e.code, e.read().decode()
    if body.lstrip().startswith("<"):
        sys.exit(f"{method} {path}: HTML response (session expired?)")
    res = json.loads(body or "{}")
    # A failure can be HTTP 200 with error:true.
    if status >= 400 or (isinstance(res, dict) and res.get("error") is True):
        sys.exit(f"{method} {path}: HTTP {status} {res.get('message')}")
    return res


def rows(res):
    d = res.get("data")
    inner = d.get("data") if isinstance(d, dict) else d
    return inner if isinstance(inner, list) else []


def state_of(base, token, vid):
    for path, q in (("user/visits", "?size=200&widget=1"), ("user/visits/serving", "?widget=1")):
        for v in rows(call(base, path, token=token, query=q)):
            if v.get("id") == vid:
                return STATES.get(v.get("state"), str(v.get("state"))), v
    return "GONE (served, no-show or cancelled)", None


def step(base, token, vid, label, path, expect, payload=None):
    call(base, path.format(vid), "PUT", token, payload or {})
    got, v = state_of(base, token, vid)
    ok = got == expect or (expect == "GONE" and got.startswith("GONE"))
    extra = ""
    if v:
        extra = f" called_at={v.get('called_at')} started_at={v.get('started_at')}"
    print(f"[{' OK ' if ok else 'FAIL'}] visit {vid} {label}: {got}{extra}")
    return ok


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base", default="https://chup.tech/api/v1/")
    p.add_argument("--email", required=True)
    p.add_argument("--password", required=True)
    p.add_argument("--visit-a", type=int, required=True)
    p.add_argument("--visit-b", type=int, required=True)
    p.add_argument("--yes", action="store_true", help="confirm writes to staging")
    a = p.parse_args()
    base = a.base if a.base.endswith("/") else a.base + "/"
    if "chup.online" in base:
        sys.exit("Refusing production. Point --base at staging.")
    if not a.yes:
        sys.exit("This writes queue state and sends WhatsApp. Re-run with --yes.")

    token = (call(base, "user/auth/widget-login", "POST",
                  payload={"email": a.email, "password": a.password})
             .get("data") or {}).get("api_token")
    if not token:
        sys.exit("No api_token from widget-login")

    for vid in (a.visit_a, a.visit_b):
        got, _ = state_of(base, token, vid)
        if got not in ("IN_QUEUE", "ARRIVED", "DELAYED", "EARLY_ARRIVED"):
            sys.exit(f"visit {vid} is {got}, not waiting in this queue")

    results = [
        step(base, token, a.visit_a, "Alert", "user/visits/{}/alert", "ALERTED"),
        step(base, token, a.visit_a, "Start", "user/visits/{}/serving", "SERVING"),
        step(base, token, a.visit_a, "End Visit", "user/visits/{}/served", "GONE"),
        step(base, token, a.visit_b, "Alert", "user/visits/{}/alert", "ALERTED"),
        step(base, token, a.visit_b, "No-Show", "user/visits/{}/no-show", "GONE"),
    ]
    print("\nAll four actions behave as the widget expects." if all(results)
          else "\nFAILED: see the lines above.")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
