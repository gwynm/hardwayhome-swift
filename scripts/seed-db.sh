#!/bin/bash
# Seed the simulator database with test workouts.
# Usage: ./scripts/seed-db.sh

set -e

DEVICE_ID="139CA751-3850-4D69-802A-ECC47B3672CE"
BUNDLE_ID="com.gwynmorfey.hardwayhome.native"

# Get app container
APP_CONTAINER=$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data 2>/dev/null)
DB_PATH="$APP_CONTAINER/Library/Application Support/hardwayhome.db"

if [ ! -f "$DB_PATH" ]; then
    echo "Database not found at: $DB_PATH"
    echo "Make sure the app has been launched at least once."
    exit 1
fi

echo "Seeding database: $DB_PATH"

# Kill the app first so it doesn't hold a lock
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" 2>/dev/null || true
sleep 1

python3 - "$DB_PATH" << 'PYEOF'
import sqlite3
import sys
import math
import random

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Clear existing data
c.execute("DELETE FROM pulses")
c.execute("DELETE FROM trackpoints")
c.execute("DELETE FROM workouts")

# Helper to generate a route that starts at a point and heads in a direction
def generate_route(start_lat, start_lng, bearing_deg, num_points, interval_sec, start_time_iso):
    """Generate trackpoints along a bearing. Returns list of (time, lat, lng, speed, err)."""
    points = []
    lat = start_lat
    lng = start_lng
    bearing = math.radians(bearing_deg)
    
    # ~3.5 m/s running pace with some variation
    base_speed = 3.5
    
    from datetime import datetime, timedelta, timezone
    t = datetime.fromisoformat(start_time_iso.replace('Z', '+00:00'))
    
    for i in range(num_points):
        speed = base_speed + random.uniform(-0.5, 0.5)
        err = random.uniform(3, 12)
        
        time_str = t.strftime('%Y-%m-%dT%H:%M:%SZ')
        points.append((time_str, lat, lng, speed, err))
        
        # Move ~speed * interval metres in bearing direction
        dist_m = speed * interval_sec
        dlat = (dist_m * math.cos(bearing)) / 111320
        dlng = (dist_m * math.sin(bearing)) / (111320 * math.cos(math.radians(lat)))
        lat += dlat
        lng += dlng
        t += timedelta(seconds=interval_sec)
    
    return points

def generate_pulses(start_time_iso, num_points, interval_sec, base_bpm=145):
    """Generate pulse readings."""
    from datetime import datetime, timedelta, timezone
    t = datetime.fromisoformat(start_time_iso.replace('Z', '+00:00'))
    pulses = []
    for i in range(num_points):
        bpm = base_bpm + random.randint(-10, 15) + (i * 2 // num_points)
        time_str = t.strftime('%Y-%m-%dT%H:%M:%SZ')
        pulses.append((time_str, bpm))
        t += timedelta(seconds=interval_sec)
    return pulses

# --- Workout 1: 5km run, finished ---
print("Creating workout 1: 5km run...")
c.execute("""INSERT INTO workouts (started_at, finished_at, distance, avg_sec_per_km, avg_bpm) 
             VALUES ('2026-02-10T07:30:00Z', '2026-02-10T08:02:30Z', 5200, 375, 152)""")
w1_id = c.lastrowid

route1 = generate_route(51.5074, -0.1278, 45, 390, 5, '2026-02-10T07:30:00Z')
for time_str, lat, lng, speed, err in route1:
    c.execute("INSERT INTO trackpoints (workout_id, created_at, lat, lng, speed, err) VALUES (?, ?, ?, ?, ?, ?)",
              (w1_id, time_str, lat, lng, speed, err))

pulses1 = generate_pulses('2026-02-10T07:30:00Z', 1950, 1, 148)
for time_str, bpm in pulses1:
    c.execute("INSERT INTO pulses (workout_id, created_at, bpm) VALUES (?, ?, ?)",
              (w1_id, time_str, bpm))

# --- Workout 2: 3km run, finished ---
print("Creating workout 2: 3km run...")
c.execute("""INSERT INTO workouts (started_at, finished_at, distance, avg_sec_per_km, avg_bpm) 
             VALUES ('2026-02-13T17:15:00Z', '2026-02-13T17:35:00Z', 3100, 387, 158)""")
w2_id = c.lastrowid

route2 = generate_route(51.5155, -0.1410, 135, 240, 5, '2026-02-13T17:15:00Z')
for time_str, lat, lng, speed, err in route2:
    c.execute("INSERT INTO trackpoints (workout_id, created_at, lat, lng, speed, err) VALUES (?, ?, ?, ?, ?, ?)",
              (w2_id, time_str, lat, lng, speed, err))

pulses2 = generate_pulses('2026-02-13T17:15:00Z', 1200, 1, 155)
for time_str, bpm in pulses2:
    c.execute("INSERT INTO pulses (workout_id, created_at, bpm) VALUES (?, ?, ?)",
              (w2_id, time_str, bpm))

# --- Workout 3: 8km run, finished ---
print("Creating workout 3: 8km run...")
c.execute("""INSERT INTO workouts (started_at, finished_at, distance, avg_sec_per_km, avg_bpm) 
             VALUES ('2026-02-14T06:00:00Z', '2026-02-14T06:55:00Z', 8400, 393, 155)""")
w3_id = c.lastrowid

route3 = generate_route(51.5010, -0.1190, 315, 660, 5, '2026-02-14T06:00:00Z')
for time_str, lat, lng, speed, err in route3:
    c.execute("INSERT INTO trackpoints (workout_id, created_at, lat, lng, speed, err) VALUES (?, ?, ?, ?, ?, ?)",
              (w3_id, time_str, lat, lng, speed, err))

pulses3 = generate_pulses('2026-02-14T06:00:00Z', 3300, 1, 152)
for time_str, bpm in pulses3:
    c.execute("INSERT INTO pulses (workout_id, created_at, bpm) VALUES (?, ?, ?)",
              (w3_id, time_str, bpm))

conn.commit()
conn.close()

print(f"Done! Created 3 workouts with trackpoints and pulses.")
print(f"  Workout {w1_id}: 5.2km, 32:30")
print(f"  Workout {w2_id}: 3.1km, 20:00")
print(f"  Workout {w3_id}: 8.4km, 55:00")
PYEOF

echo "Relaunching app..."
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
echo "Done!"
