# MEMORY - Long-Term Memory

> This file is maintained by the assistant. Add important facts, decisions,
> and observations that should persist across conversations.

## Setup
- Data sources: Hevy (workouts), HealthClaw (Apple Health - sleep, HR, HRV, weight, steps, body battery)
- Messaging: Telegram
- Shell access to homelab is disabled until exec approvals are working

## Imperative Changes (not tracked in dotfiles)
- Synology: openclaw container SSH key added to chris@synology:~/.ssh/authorized_keys
  - Key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjvbv2K5oydAynpFJIJKHlvbvex6HheCYIJq7Sm48ZT openclaw-container
  - Added 2026-04-03, can be removed if exec access is never re-enabled
