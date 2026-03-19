---
name: deployment-monitor
description: Monitor a deployment, CI pipeline, or PR status. Sets up recurring
  checks and reports only on state changes.
disable-model-invocation: true
---

Monitor: $ARGUMENTS

Set up a recurring check using CronCreate:
1. Determine what to monitor (CI status, PR review, deployment health)
2. Choose an appropriate interval (default: 5 minutes)
3. Create the cron job
4. Report the initial state

The monitoring will continue until:
- You explicitly cancel it
- The monitored process completes (success or failure)
- The session ends

Report only STATE CHANGES, not "still running" messages.
