---
name: weather
description: "Get current weather and forecasts. Use when the user asks about weather, temperature, rain, or what to wear."
---

# Weather Skill

Uses the Open-Meteo API. No API key needed.

## Current Weather + 7-Day Forecast
```bash
curl -s "https://api.open-meteo.com/v1/forecast?latitude=45.7489&longitude=21.2087&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,precipitation&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,weather_code,sunrise,sunset&timezone=Europe/Bucharest"
```

## Hourly Forecast (next 24h)
```bash
curl -s "https://api.open-meteo.com/v1/forecast?latitude=45.7489&longitude=21.2087&hourly=temperature_2m,precipitation_probability,weather_code,wind_speed_10m&forecast_hours=24&timezone=Europe/Bucharest"
```

## For Other Locations
Replace latitude/longitude. Find coordinates at https://open-meteo.com/en/docs/geocoding-api:
```bash
curl -s "https://geocoding-api.open-meteo.com/v1/search?name=CITY_NAME&count=1"
```

## Weather Codes
- 0: Clear sky
- 1-3: Partly cloudy
- 45-48: Fog
- 51-55: Drizzle
- 61-65: Rain
- 71-75: Snow
- 80-82: Rain showers
- 95: Thunderstorm
- 96-99: Thunderstorm with hail

## Default Location
Timisoara, Romania (45.7489, 21.2087). If the user asks about weather without specifying a location, use this.
