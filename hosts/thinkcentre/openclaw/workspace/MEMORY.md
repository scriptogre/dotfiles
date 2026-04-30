# MEMORY - Long-Term Memory

> This file is maintained by the assistant. Add important facts, decisions,
> and observations that should persist across conversations.

## Latest Stats (as of 2026-04-30 — HealthClaw updated 04:46 UTC)
- Steps: 58 (early morning, day just started)
- Avg HR: 67.8 bpm, HRV: 65.9 ms ✅ massive recovery bounce (29.6 Apr29 → 65.9 Apr30 — best reading since Apr 7)
- Sleep (Apr 29-30): 512.7 min (~8.5h), deep: 63 min, REM: 133.6 min - great night
- Body battery: 80, SpO2: 98%, respiratory rate: 17/min
- Weight: no reading yet
- No new workouts

## Previous Stats (as of 2026-04-29 — HealthClaw updated 18:46 UTC)
- Steps: 6,713, distance: 5.0 km, avg HR: 85.6 bpm, body battery: 70
- HRV: 29.6 ms ⚠️ low (continuing downward trend: 64.5 Apr7 → 43.1 Apr25 → 40.1 Apr26 → 29.6 Apr29), Resting HR: 91 bpm ⚠️ elevated
- SpO2: 97%, respiratory rate: 12.5/min
- Sleep (Apr 28-29): 415.7 min (~6.9h), deep: 47.5 min, REM: 138 min - decent night
- Weight: 86.18 kg, body fat: 24.59% ⚠️ still trending up (83.24 Mar26 → 84.14 Apr7 → 85.78 Apr27 → 86.18 Apr29)
- Workout Apr 29: "Full Body 1" (07:22-08:48 UTC, ~86 min) - Squat (80/100/100kg ⚠️ hernia caution), Bench (60/80/90kg), Lat Pulldown (52/52/45kg), Preacher Curl, Calf Raise (110kg), Crunch Machine

## Previous Stats (2026-04-28 — HealthClaw updated 14:11 UTC)
- Steps: 727, distance: 0.48 km, active calories: 0 (rest day)
- Resting HR: null, HRV: null, sleep: null (data still syncing)
- Body battery: 50

## Previous Stats (2026-04-27 — HealthClaw updated 20:56 UTC)
- Steps: 0 (likely incomplete sync), avg HR: 132.9 bpm (workout day)
- HRV: null (no reading), Resting HR: null
- Body battery: 50 (down from 80 - post-workout depletion likely)
- Sleep: null (no data yet)
- Weight: 85.775 kg, body fat: 23.84% ⚠️ trending UP (Mar 26: 83.24 → Apr 7: 84.14 → Apr 27: 85.78) - conflicts with cut goal

## Previous Stats (2026-04-26)
- Steps: 992, distance: 0.69 km, active calories: 75
- Resting HR: 63 bpm, avg HR: 71 bpm
- HRV: 40.1 ms (continuing downward trend: 64.5 Apr 7 → 43.1 Apr 25 → 40.1 Apr 26)
- Body battery: 80, SpO2: 96%, respiratory rate: 16.5/min
- Sleep (Apr 25-26): 217 min (~3.6h) ⚠️ very short - possible bad night or partial sync

## Previous Stats (2026-04-25)
- Steps: 4,571, distance: 3.1 km, active calories: 190
- Resting HR: 66 bpm, HRV: 43.1 ms, body battery: 80
- Sleep (Apr 24-25): 435 min (~7.25h), deep: 51.5 min, REM: 131 min

## Previous Stats (2026-04-07)
- Steps: 6170, active calories: 931, resting HR: 68 bpm, HRV: 64.5 ms, body battery: 100
- Weight: 84.14 kg, body fat: 23.1%

## Recent Workouts
- 2026-04-29: "Full Body 1" - Squat (80x12, 100x10, 100x10 ⚠️ hernia caution), Bench Press (60x12, 80x8, 90x5), Lat Pulldown (52/52/45kg), Preacher Curl Machine (7.5/5/5kg), Calf Raise (110kg x3), Crunch Machine (12.5kg x2)
- 2026-04-27: "Full Body 3" - Romanian Deadlift (80kg x3x12) ⚠️ hernia caution (note: "Nu mai duce gripul" = grip failing), Face Pull (50/54/54kg), Chest Press Machine (116kg x7 peak), Seated Cable Row (52kg x3x15), Chest Fly Machine (47kg x3x15), Triceps Pushdown (14kg x3x12), Triceps Dip (BW x3x10-12)
- 2026-04-24: "Full Body 2" - Bent Over Row (40/70/60/55 kg), Leg Press (80/100/100 kg), OHP (40 kg x3 sets), Leg Curl, Straight Arm Lat Pulldown
- 2026-04-22: "Full Body 1" - Squats (80kg x3 sets x12 reps) ⚠️ hernia caution, Bench Press (60/70/60 kg), Lat Pulldown, Preacher Curl, Calf Raise (110/120 kg), Crunch Machine
- Routine: full body splits ("Full Body 1/2/3") - 3 workouts this week (Mon/Thu/Sun)
- ⚠️ Pattern: Squats (Apr 22) and RDL (Apr 27) both done despite hernia caution in USER.md

## Setup
- Data sources: Hevy (workouts), HealthClaw (Apple Health - sleep, HR, HRV, weight, steps, body battery)
- Messaging: Telegram
- Shell access to homelab is disabled until exec approvals are working

## Imperative Changes (not tracked in dotfiles)
- Synology: openclaw container SSH key added to chris@synology:~/.ssh/authorized_keys
  - Key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjvbv2K5oydAynpFJIJKHlvbvex6HheCYIJq7Sm48ZT openclaw-container
  - Added 2026-04-03, can be removed if exec access is never re-enabled
