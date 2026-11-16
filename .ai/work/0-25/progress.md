# #0-25 A stale `notification_queue` write can overwrite a terminal status

Append-only. One line per step: `- [<stage> r<round>] <result>` — never rewrite an earlier line. The
autopilot reads the last `NEXT:` line to resume an interrupted run.

- [picker] picked; branch `<prefix>/<item-id>-<slug>`; base `<sha>`
- [architect] plan: <one line>; ADR: <none | NNNN (Proposed)>
- [implementer r0] commits <sha>..<sha>; <n> files; tests: <classes>
- [tests r0] PASS | FAIL (exit <code>, log `.ai/runs/<item>/tests-r0.log`)
- [review r1] general APPROVE · architecture APPROVE · security CHANGES_REQUESTED (sec-7f3a) · …
- [implementer r1] fixed sec-7f3a in <sha>
- [acceptance] ACCEPT | REJECT (AC2 missing evidence) | NEEDS_HUMAN (<reason>)
NEXT: <stage>
- [start] started by start-item.sh; branch `refactor/0-25-notification-queue-stale-write-guard`; base `84f86049282cde6081dc1bf560bcde9b2ecafcc2`
NEXT: architect
- [architect] plan: four tenant-scoped conditional UPDATEs from PENDING in NotificationQueueRepository (AuthEmailOutboxRepository precedent), persistence methods return boolean, 0 rows logged and counted in notification.queue.stale_write{operation}, no audit/alert on a stale markUndeliverable, entity mutators removed, architecture.md criterion; ADR: 0059 (Proposed); modules: notification-service, root; rules: GEN-01, GEN-02, GEN-04, GEN-05, GEN-07, GEN-08, GEN-20, GEN-32, ARC-02, ARC-26, ARC-29, ARC-22, SEC-06, SEC-31, DOC-01, DOC-10, DOC-11, DOC-30
NEXT: implementer
