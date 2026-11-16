# Handoff: <item id>

Facts only. No reasoning about why the change is good: reviewers judge it themselves. Updated by the
implementer after every round.

## Changed
- <file / endpoint / topic / migration / config key>: <what changed>

## How to verify
- `./mvnw test -pl <module> -Dtest=<Class>` — <what it shows>

## Tests changed and why
- (only if an existing test changed) <test>: <the acceptance criterion or requirement that changed it>

## Deliberately out of scope
- <thing>: <backlog item or reason>

## Noticed, not touched
- <defect elsewhere>: <file:line> — proposed backlog item: <one line>

## Follow-up needed
<!-- Work this item showed is needed but is not part of it (.ai/rules/planning.md, "Follow-ups"); at most 3.
     The shipper turns each entry into a backlog item with **Autopilot:** proposed. Delete this comment
     and leave the section empty when there is none. -->
### <title, as a backlog item title>
- Why: <what is missing and what fails or stays incomplete without it, 1–2 lines>
- Touches: <module (packages), …>
- Risk: <low|high> · Complexity: <low|medium|high>
- Draft criteria:
  - AC1. <observable, checkable by a test>

## Disputed
- <finding id>: <reason, citing code or a rule>
