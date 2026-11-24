#!/usr/bin/env bash
# ============================================================
# Withdrawn (backlog #0-313; ADR-0062 point 5 as amended, 2026-11-23). This script ran the old path (/backlog-autopilot)
# in the rollback's devcontainer on the build VM (backlog #0-277), sharing the VM with the dispatcher by time. Since
# #0-313 the VM's egress gives no uid but `dispatcher`'s an Anthropic host (AC7): a task holds `factory`'s daemon
# socket, so a devcontainer of that daemon, the rollback's included, may not reach Anthropic around the dispatcher's
# proxy. Claude Code could no longer log in or call the model there. The old path runs only in the owner's devcontainer
# on the Mac from now on (docs/ai-factory.md, Setup), earlier than M4 would have moved it (M4 removes only the rest,
# migration/m4.md). The script that did this is in the history before this change (commit 5ccbf447 and earlier).
# It refuses every call, changing nothing, so a call from habit says why instead of failing on the VM.
# Tested by .github/scripts/test-rollback-scripts.sh.
# ============================================================
echo "rollback-exec.sh: withdrawn (backlog #0-313, ADR-0062 point 5 as amended): the build VM gives factory's devcontainers no Anthropic host, so the old path (/backlog-autopilot) runs only in the owner's devcontainer on the Mac (docs/ai-factory.md, Setup)" >&2
exit 1
