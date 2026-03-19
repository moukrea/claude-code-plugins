---
name: logs
description: Summarize recent harness hook activity from .harness/logs/harness.log.
  Shows hook invocations, decisions, durations, and patterns. Use to debug harness
  behavior or understand what happened during a session.
disable-model-invocation: true
---

Summarize the harness activity log.

## Recent Log Entries (last 50)
!`tail -50 .harness/logs/harness.log 2>/dev/null || echo "No log file found at .harness/logs/harness.log"`

## Hook Invocation Counts
!`awk -F'"hook":"' '{split($2,a,"\""); print a[1]}' .harness/logs/harness.log 2>/dev/null | sort | uniq -c | sort -rn || echo "No data"`

## Decision Summary
!`awk -F'"decision":"' '{split($2,a,"\""); print a[1]}' .harness/logs/harness.log 2>/dev/null | sort | uniq -c | sort -rn || echo "No data"`

## Slow Hooks (>1000ms)
!`awk -F'"duration_ms":' 'NF>1{split($2,a,"[,}]"); if(a[1]+0 > 1000) print}' .harness/logs/harness.log 2>/dev/null | tail -10 || echo "None"`

## Blocks (exit 2 decisions)
!`grep '"decision":"block"' .harness/logs/harness.log 2>/dev/null | tail -10 || echo "None"`

## Your Task

Analyze the log data above and provide:
1. **Summary**: total hook invocations, time range covered
2. **Hot spots**: which hooks fire most, which are slowest
3. **Blocks**: what was blocked and why
4. **Patterns**: any repeated failures or unusual activity
5. **Recommendations**: anything that could be tuned or investigated
