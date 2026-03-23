---
name: fitness-coach
description: "Track and analyze fitness data from Hevy (workouts, routines, exercises, PRs) and HealthClaw (Apple Health - sleep, heart rate, HRV, steps, weight, body battery). Use whenever the user asks about workouts, progress, body weight, sleep, heart rate, recovery, or fitness trends."
---

# Fitness Coach Skill

## When to Use
- User asks about workouts, progress, PRs, routines
- User asks about weight, sleep, heart rate, HRV, recovery, steps
- Cron job triggers a check-in or review
- User asks to update their routine

## HealthClaw API (Apple Health data)

Base URL (from inside Docker): `http://healthclaw:8099`
Auth: Header `X-API-Key: uaXU0kLQYYcxFEbD49Sc_hWZRwXzO3y_s09NFyJNkzs`

### Latest Daily Summary
```bash
curl -sf http://healthclaw:8099/api/health/latest \
  -H "X-API-Key: uaXU0kLQYYcxFEbD49Sc_hWZRwXzO3y_s09NFyJNkzs"
```
Returns: steps, distance, calories, exercise minutes, resting HR, avg HR, HRV, sleep duration + stages, weight, body fat, body battery, SpO2, respiratory rate.

### Daily Summaries (last N days)
```bash
curl -sf "http://healthclaw:8099/api/health/summary?days=7" \
  -H "X-API-Key: uaXU0kLQYYcxFEbD49Sc_hWZRwXzO3y_s09NFyJNkzs"
```

### Sleep Sessions
```bash
curl -sf "http://healthclaw:8099/api/health/sleep?days=7" \
  -H "X-API-Key: uaXU0kLQYYcxFEbD49Sc_hWZRwXzO3y_s09NFyJNkzs"
```

### Workouts
```bash
curl -sf "http://healthclaw:8099/api/health/workouts?days=7" \
  -H "X-API-Key: uaXU0kLQYYcxFEbD49Sc_hWZRwXzO3y_s09NFyJNkzs"
```

### Mood
```bash
curl -sf "http://healthclaw:8099/api/health/mood?days=7" \
  -H "X-API-Key: uaXU0kLQYYcxFEbD49Sc_hWZRwXzO3y_s09NFyJNkzs"
```

## Hevy API (workout tracking)

Base URL: `https://api.hevyapp.com`
Auth: Header `api-key: $HEVY_API_KEY`
Rate limit: Respect 429 responses. Max page size is 10.

### List Recent Workouts
```bash
curl -s "https://api.hevyapp.com/v1/workouts?page=1&pageSize=5" \
  -H "api-key: $HEVY_API_KEY"
```

### Get Workout Details
```bash
curl -s "https://api.hevyapp.com/v1/workouts/{workoutId}" \
  -H "api-key: $HEVY_API_KEY"
```

### Check for New Workouts (Polling)
```bash
curl -s "https://api.hevyapp.com/v1/workouts/events?page=1&since=2026-03-19" \
  -H "api-key: $HEVY_API_KEY"
```

### Get Exercise History
```bash
curl -s "https://api.hevyapp.com/v1/exercise_history/{exerciseTemplateId}?page=1&pageSize=5" \
  -H "api-key: $HEVY_API_KEY"
```

### List Routines
```bash
curl -s "https://api.hevyapp.com/v1/routines" \
  -H "api-key: $HEVY_API_KEY"
```

### Create a Routine
```bash
curl -s -X POST "https://api.hevyapp.com/v1/routines" \
  -H "api-key: $HEVY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"routine":{"title":"Example","exercises":[]}}'
```

### Update a Routine
```bash
curl -s -X PUT "https://api.hevyapp.com/v1/routines/{routineId}" \
  -H "api-key: $HEVY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"routine":{...}}'
```

## Analysis Guidelines
- Always compare to previous week / previous month - trends matter more than single readings
- For weight: use 7-day moving average to smooth daily fluctuations
- For workouts: track total volume (sets x reps x weight) per muscle group per week
- For recovery: combine HRV + resting HR + sleep quality + body battery
- Flag PRs enthusiastically
- Flag potential overtraining: declining performance + high resting HR + poor sleep + low HRV
- Flag stalls: same weight/reps for 3+ weeks on a lift
