# Notification and alerting design rules

Distills the Google SRE Book's four golden signals plus PagerDuty's alert-fatigue guidance.

## What to watch: the four golden signals
Latency, traffic, errors, saturation. Alert on symptoms, the user-visible effect, not causes, the internal reason. Causes belong in the linked playbook, not the alert condition itself.

## Severity to channel

| Severity | Channel | Escalation |
|---|---|---|
| Critical, symptom-facing, breaks the thing | Page plus a dedicated incident channel | Immediate |
| Error but tolerable | High-priority chat / ticket | Next business hours |
| Warning, or internal cause only | Chat/log | None |

## The actionable-alert rule
Every alert needs a one-line "what to do" playbook note. If a responder has to dig before they can act, the alert is not ready to ship. Fix the alert; do not just tolerate the noise, that is what causes alert fatigue.

## At personal scale
There is no pager. "Page" = a phone-audible push (ntfy, Telegram priority, or equivalent); anything below critical lands in a chat digest instead of inventing a new channel per tool.

## Sources
- [Google SRE Book, Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)
- [PagerDuty: Understanding Alert Fatigue](https://www.pagerduty.com/resources/digital-operations/learn/alert-fatigue/)

Verified: 2026-07-29.
