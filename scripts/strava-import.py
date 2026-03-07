#!/usr/bin/env python3
"""
Import Strava activities into a HardWayHome-compatible SQLite database.

Resumable: re-run to pick up where you left off. Respects Strava rate limits.

Usage:
    pip install requests
    python scripts/strava-import.py --auth       # first time: authorize with Strava
    python scripts/strava-import.py              # import activities (resumes if re-run)
    python scripts/strava-import.py -o my.db     # custom output path
"""

import argparse
import json
import os
import sqlite3
import sys
import time
import webbrowser
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

try:
    import requests
except ImportError:
    sys.exit("Missing dependency: pip install requests")

# ---------------------------------------------------------------------------
# Strava credentials
# ---------------------------------------------------------------------------

CLIENT_ID = ""
CLIENT_SECRET = ""
REDIRECT_URI = "http://localhost:8642/callback"

TOKENS_FILE = Path(__file__).parent / ".strava-tokens.json"

# ---------------------------------------------------------------------------
# Activity type filtering — exclude cycling, include everything else
# ---------------------------------------------------------------------------

EXCLUDED_SPORT_TYPES = {
    "Ride",
    "MountainBikeRide",
    "GravelRide",
    "EBikeRide",
    "EMountainBikeRide",
    "VirtualRide",
    "Velomobile",
    "Handcycle",
}

# ---------------------------------------------------------------------------
# Rate limit tracking
# ---------------------------------------------------------------------------

RATE_LIMIT_BUFFER = 5  # stop this many requests before the 15-min limit


class RateLimiter:
    def __init__(self):
        self.limit_15m = 100
        self.usage_15m = 0
        self.limit_daily = 1000
        self.usage_daily = 0

    def update(self, headers):
        if "X-ReadRateLimit-Limit" in headers:
            parts = headers["X-ReadRateLimit-Limit"].split(",")
            self.limit_15m = int(parts[0])
            self.limit_daily = int(parts[1])
        if "X-ReadRateLimit-Usage" in headers:
            parts = headers["X-ReadRateLimit-Usage"].split(",")
            self.usage_15m = int(parts[0])
            self.usage_daily = int(parts[1])

    def check(self):
        if self.usage_daily >= self.limit_daily - RATE_LIMIT_BUFFER:
            print(f"\nDaily rate limit nearly exhausted ({self.usage_daily}/{self.limit_daily}).")
            print("Re-run tomorrow to continue.")
            sys.exit(0)
        if self.usage_15m >= self.limit_15m - RATE_LIMIT_BUFFER:
            wait = self._seconds_until_next_15m_window() + 5
            print(f"\n15-min rate limit nearly exhausted ({self.usage_15m}/{self.limit_15m}). "
                  f"Waiting {wait}s...")
            time.sleep(wait)
            self.usage_15m = 0

    def _seconds_until_next_15m_window(self):
        now = datetime.now(timezone.utc)
        minute = now.minute
        next_boundary = ((minute // 15) + 1) * 15
        remaining_minutes = next_boundary - minute
        return remaining_minutes * 60 - now.second


rate_limiter = RateLimiter()

# ---------------------------------------------------------------------------
# OAuth authorization flow
# ---------------------------------------------------------------------------


def do_auth():
    """Run the OAuth flow: open browser, catch callback, exchange code for tokens."""
    auth_url = (
        f"https://www.strava.com/oauth/authorize"
        f"?client_id={CLIENT_ID}"
        f"&redirect_uri={REDIRECT_URI}"
        f"&response_type=code"
        f"&scope=activity:read_all"
    )

    code_holder = {}

    class CallbackHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            qs = parse_qs(urlparse(self.path).query)
            if "code" in qs:
                code_holder["code"] = qs["code"][0]
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(b"<h2>Authorization successful. You can close this tab.</h2>")
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"No code in callback")

        def log_message(self, format, *args):
            pass

    print(f"Opening browser for Strava authorization...")
    print(f"  (If it doesn't open, visit: {auth_url})")
    webbrowser.open(auth_url)

    server = HTTPServer(("localhost", 8642), CallbackHandler)
    print("Waiting for authorization callback on localhost:8642...")
    while "code" not in code_holder:
        server.handle_request()
    server.server_close()

    code = code_holder["code"]
    print("Got authorization code, exchanging for tokens...")

    resp = requests.post(
        "https://www.strava.com/oauth/token",
        data={
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "code": code,
            "grant_type": "authorization_code",
        },
    )
    resp.raise_for_status()
    data = resp.json()

    tokens = {
        "access_token": data["access_token"],
        "refresh_token": data["refresh_token"],
        "expires_at": data["expires_at"],
    }
    save_tokens(tokens)
    athlete = data.get("athlete", {})
    print(f"Authorized as: {athlete.get('firstname', '')} {athlete.get('lastname', '')}")
    print(f"Tokens saved to {TOKENS_FILE}")
    return tokens


# ---------------------------------------------------------------------------
# Token management
# ---------------------------------------------------------------------------


def load_tokens():
    if TOKENS_FILE.exists():
        with open(TOKENS_FILE) as f:
            return json.load(f)
    return None


def save_tokens(tokens):
    with open(TOKENS_FILE, "w") as f:
        json.dump(tokens, f, indent=2)


def ensure_valid_token(tokens):
    if time.time() < tokens.get("expires_at", 0) - 60:
        return tokens

    print("Refreshing access token...")
    resp = requests.post(
        "https://www.strava.com/oauth/token",
        data={
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
            "grant_type": "refresh_token",
            "refresh_token": tokens["refresh_token"],
        },
    )
    resp.raise_for_status()
    data = resp.json()
    tokens["access_token"] = data["access_token"]
    tokens["refresh_token"] = data["refresh_token"]
    tokens["expires_at"] = data["expires_at"]
    save_tokens(tokens)
    print(f"Token refreshed, expires at {datetime.fromtimestamp(data['expires_at'], tz=timezone.utc).isoformat()}")
    return tokens


# ---------------------------------------------------------------------------
# Strava API helpers
# ---------------------------------------------------------------------------


def strava_get(tokens, url, params=None):
    rate_limiter.check()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    resp = requests.get(url, headers=headers, params=params)
    rate_limiter.update(resp.headers)

    if resp.status_code == 401:
        tokens = ensure_valid_token({**tokens, "expires_at": 0})
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        resp = requests.get(url, headers=headers, params=params)
        rate_limiter.update(resp.headers)

    if resp.status_code == 429:
        print("Got 429 despite rate tracking. Waiting 15 minutes...")
        time.sleep(15 * 60 + 10)
        return strava_get(tokens, url, params)

    resp.raise_for_status()
    return resp.json(), tokens


def fetch_all_activities(tokens):
    """Fetch the full list of summary activities, paginated."""
    all_activities = []
    page = 1
    per_page = 200
    while True:
        print(f"  Fetching activity list page {page}...")
        data, tokens = strava_get(
            tokens,
            "https://www.strava.com/api/v3/athlete/activities",
            params={"page": page, "per_page": per_page},
        )
        if not data:
            break
        all_activities.extend(data)
        if len(data) < per_page:
            break
        page += 1
    return all_activities, tokens


def fetch_activity_detail(tokens, activity_id):
    data, tokens = strava_get(
        tokens, f"https://www.strava.com/api/v3/activities/{activity_id}"
    )
    return data, tokens


def fetch_activity_streams(tokens, activity_id):
    keys = "time,latlng,heartrate,velocity_smooth"
    rate_limiter.check()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    resp = requests.get(
        f"https://www.strava.com/api/v3/activities/{activity_id}/streams",
        headers=headers,
        params={"keys": keys, "key_by_type": "true"},
    )
    rate_limiter.update(resp.headers)

    if resp.status_code == 404:
        return {}, tokens

    if resp.status_code == 401:
        tokens = ensure_valid_token({**tokens, "expires_at": 0})
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        resp = requests.get(
            f"https://www.strava.com/api/v3/activities/{activity_id}/streams",
            headers=headers,
            params={"keys": keys, "key_by_type": "true"},
        )
        rate_limiter.update(resp.headers)
        if resp.status_code == 404:
            return {}, tokens

    resp.raise_for_status()
    data = resp.json()
    streams = {}
    if isinstance(data, list):
        for stream in data:
            streams[stream["type"]] = stream["data"]
    elif isinstance(data, dict):
        for key, stream in data.items():
            streams[key] = stream.get("data", stream) if isinstance(stream, dict) else stream
    return streams, tokens


# ---------------------------------------------------------------------------
# Database setup
# ---------------------------------------------------------------------------

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS workouts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at REAL NOT NULL,
    finished_at REAL,
    distance REAL,
    avg_sec_per_km REAL,
    avg_bpm REAL,
    strava_id INTEGER
);

CREATE TABLE IF NOT EXISTS trackpoints (
    id INTEGER PRIMARY KEY,
    workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    created_at REAL NOT NULL,
    lat REAL NOT NULL,
    lng REAL NOT NULL,
    speed REAL,
    err REAL
);

CREATE TABLE IF NOT EXISTS pulses (
    id INTEGER PRIMARY KEY,
    workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    created_at REAL NOT NULL,
    bpm INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS kv (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_trackpoints_workout ON trackpoints(workout_id, created_at);
CREATE INDEX IF NOT EXISTS idx_pulses_workout ON pulses(workout_id, created_at);

-- GRDB migration tracking so the app recognises this database
CREATE TABLE IF NOT EXISTS grdb_migrations (
    identifier TEXT NOT NULL PRIMARY KEY
);
INSERT OR IGNORE INTO grdb_migrations (identifier) VALUES ('v3');
INSERT OR IGNORE INTO grdb_migrations (identifier) VALUES ('v4');
INSERT OR IGNORE INTO grdb_migrations (identifier) VALUES ('v5_fix_null_finished_at');
"""


def init_db(db_path):
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.executescript(SCHEMA_SQL)
    conn.commit()
    return conn


def get_imported_strava_ids(conn):
    rows = conn.execute(
        "SELECT strava_id FROM workouts WHERE strava_id IS NOT NULL"
    ).fetchall()
    return {row[0] for row in rows}


# ---------------------------------------------------------------------------
# Import logic
# ---------------------------------------------------------------------------

GPS_ERR = 10.0


def iso_to_epoch(iso_str):
    dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
    return dt.timestamp()


def import_activity(conn, detail, streams, strava_id):
    start_epoch = iso_to_epoch(detail["start_date"])
    elapsed = detail.get("elapsed_time") or detail.get("moving_time") or 0
    finish_epoch = start_epoch + elapsed
    distance = detail.get("distance")
    avg_speed = detail.get("average_speed")
    avg_sec_per_km = (1000.0 / avg_speed) if avg_speed and avg_speed > 0 else None
    avg_bpm = detail.get("average_heartrate")

    cur = conn.execute(
        """INSERT INTO workouts (started_at, finished_at, distance, avg_sec_per_km, avg_bpm, strava_id)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (start_epoch, finish_epoch, distance, avg_sec_per_km, avg_bpm, strava_id),
    )
    workout_id = cur.lastrowid

    time_data = streams.get("time", [])
    latlng_data = streams.get("latlng", [])
    velocity_data = streams.get("velocity_smooth", [])
    hr_data = streams.get("heartrate", [])

    # Trackpoints from latlng stream
    if latlng_data and time_data:
        tp_rows = []
        for i, (lat, lng) in enumerate(latlng_data):
            t = time_data[i] if i < len(time_data) else 0
            speed = velocity_data[i] if i < len(velocity_data) else None
            tp_rows.append((workout_id, start_epoch + t, lat, lng, speed, GPS_ERR))
        conn.executemany(
            "INSERT INTO trackpoints (workout_id, created_at, lat, lng, speed, err) VALUES (?, ?, ?, ?, ?, ?)",
            tp_rows,
        )

    # Pulses from heartrate stream
    if hr_data and time_data:
        pulse_rows = []
        for i, bpm in enumerate(hr_data):
            t = time_data[i] if i < len(time_data) else 0
            pulse_rows.append((workout_id, start_epoch + t, bpm))
        conn.executemany(
            "INSERT INTO pulses (workout_id, created_at, bpm) VALUES (?, ?, ?)",
            pulse_rows,
        )

    conn.commit()
    return len(latlng_data), len(hr_data)


def format_duration(seconds):
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def format_distance(meters):
    if meters is None:
        return "0km"
    return f"{meters / 1000:.1f}km"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Import Strava activities into HardWayHome database")
    parser.add_argument("-o", "--output", default="strava-import.db", help="Output database path")
    parser.add_argument("--auth", action="store_true", help="Run OAuth authorization flow")
    args = parser.parse_args()

    if args.auth:
        do_auth()
        if not args.output or args.output == "strava-import.db":
            print("\nRun again without --auth to start importing.")
            return

    tokens = load_tokens()
    if tokens is None:
        sys.exit("No tokens found. Run with --auth first to authorize with Strava.")
    tokens = ensure_valid_token(tokens)

    db_path = args.output
    print(f"Output database: {db_path}")

    conn = init_db(db_path)
    imported = get_imported_strava_ids(conn)
    print(f"Already imported: {len(imported)} activities")

    print("Fetching activity list from Strava...")
    activities, tokens = fetch_all_activities(tokens)
    print(f"Total activities on Strava: {len(activities)}")

    # Filter out cycling
    activities = [a for a in activities if a.get("sport_type", a.get("type", "")) not in EXCLUDED_SPORT_TYPES]
    print(f"After excluding cycling: {len(activities)}")

    # Deduplicate by strava ID (API can return overlaps across pages)
    seen_ids = {}
    for a in activities:
        seen_ids[a["id"]] = a
    activities = list(seen_ids.values())

    # Deduplicate by start time: Strava often has pairs of activities with the
    # same start time (e.g. watch upload + phone auto-record). Keep the one
    # with more distance data.
    by_start = {}
    for a in activities:
        key = a.get("start_date", "")
        existing = by_start.get(key)
        if existing is None or (a.get("distance", 0) or 0) > (existing.get("distance", 0) or 0):
            by_start[key] = a
    before_dedup = len(activities)
    activities = list(by_start.values())
    if before_dedup != len(activities):
        print(f"After deduplication: {len(activities)} (removed {before_dedup - len(activities)} duplicates)")

    # Filter out already imported
    to_import = [a for a in activities if a["id"] not in imported]
    print(f"New activities to import: {len(to_import)}")

    if not to_import:
        print("Nothing to do.")
        conn.close()
        return

    # Import oldest first for a more natural ordering
    to_import.sort(key=lambda a: a.get("start_date", ""))

    total = len(to_import)
    for idx, activity in enumerate(to_import, 1):
        strava_id = activity["id"]
        name = activity.get("name", "Untitled")
        sport = activity.get("sport_type", activity.get("type", "?"))
        dist = format_distance(activity.get("distance"))
        elapsed = format_duration(activity.get("elapsed_time", 0))

        print(f"[{idx}/{total}] {name} ({sport}, {dist}, {elapsed})...", end=" ", flush=True)

        if strava_id in imported:
            print("skip (already imported)")
            continue

        try:
            detail, tokens = fetch_activity_detail(tokens, strava_id)
            streams, tokens = fetch_activity_streams(tokens, strava_id)
            n_tp, n_hr = import_activity(conn, detail, streams, strava_id)
            imported.add(strava_id)
            print(f"OK ({n_tp} trackpoints, {n_hr} pulses)")
        except Exception as e:
            print(f"FAILED: {e}")
            continue

    conn.close()
    print(f"\nDone. Database: {db_path}")
    print(f"Rate limit usage: {rate_limiter.usage_15m}/{rate_limiter.limit_15m} (15m), "
          f"{rate_limiter.usage_daily}/{rate_limiter.limit_daily} (daily)")


if __name__ == "__main__":
    main()
