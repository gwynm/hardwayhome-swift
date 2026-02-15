# TODO

## WorkoutStatsVM: progressive slowdown during long workouts

### Problem

`WorkoutStatsVM` uses GRDB's `ValueObservation` to watch the `trackpoints` and
`pulses` tables for a given workout. Every time a row is inserted (every GPS
update ~1s, every BLE heartbeat ~1s), the observation fires and the `computeStats`
callback:

1. Re-reads **all** trackpoints and pulses from SQLite.
2. Runs `TrackpointFilter.filterReliable` over the full set.
3. Runs `PaceCalc.trackpointDistance` (haversine over every consecutive pair).
4. Runs `PaceCalc.paceOverWindow` (walks backwards through all trackpoints).
5. Runs `SplitCalc.computeKmSplits` (iterates all trackpoints + pulses).

For a 25km / 2.5h workout at 5s GPS interval, that's ~1800 trackpoints and
~9000 pulses. On every insert, the full pipeline runs again. At 80ms per pass
(measured on iPhone/simulator), that's fine for now, but it scales linearly —
a 50km ultra with 1-second GPS would have ~18,000 trackpoints and the cost
per update would be significant.

### Proposed fix: incremental stats

Replace the "recompute everything" approach with incremental updates:

- **Distance**: maintain a running total. On each new trackpoint, add the
  haversine distance from the previous reliable point.
- **Pace**: only needs the trailing N metres of trackpoints, not the full
  history. Keep a ring buffer or just the tail.
- **Splits**: maintain the current split state (cumulative distance, split
  start time, pulse index). Advance on each new trackpoint.
- **BPM**: already only looks at the last N seconds — just needs the tail
  of the pulses array.
- **Trackpoints for map**: append-only, no need to re-read. Could keep the
  filtered list in memory and append new reliable points.

The GRDB observation could be replaced with a listener pattern: the
`LocationService` and `HeartRateService` already know when they insert a row,
so they could notify `WorkoutStatsVM` directly with the new data, avoiding the
DB round-trip entirely.

### Impact

Low priority for now — 80ms per update is imperceptible on current workouts.
Becomes relevant for ultra-distance events (50km+) or if GPS interval is
reduced below 5 seconds.
