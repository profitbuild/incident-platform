# ============================================================
# Devcontainer for the AI factory: the autopilot runs here, not on the host account.
# What it isolates: the host's files (only the repository is mounted), the host's credentials (SSH keys,
# browser sessions, other projects), and outbound network (init-firewall.sh: default deny, allow-list).
# What it does not isolate: the host's Docker is reachable (devcontainer feature docker-outside-of-docker)
# so Testcontainers can start Postgres/Kafka on it — whoever controls it can start a container that mounts any directory Docker Desktop
# shares. Restrict Docker Desktop's file sharing to the projects directory (docs/ai-factory.md, Setup).
# Arch: builds natively on arm64 (Apple silicon) and amd64.
# It also builds the dispatcher's task container (task.json beside it, backlog #0-282, ADR-0062): a change here, or in
# init-firewall.sh, changes every task too.
# ============================================================
FROM eclipse-temurin:21-jdk-noble

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

# unzip for ./mvnw (backlog #0-238): without it the wrapper downloads Maven's .tar.gz instead of the .zip
# (mvnw, "select .zip or .tar.gz") and checks it against distributionSha256Sum, the .zip's hash, so every
# fresh environment (a new VM, a new .m2 volume) failed the check; a Mac whose volume already held Maven never saw it.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git jq curl ca-certificates gnupg sudo less vim-tiny unzip \
        iptables ipset iproute2 dnsutils \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI from GitHub's apt repository (signed).
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh && rm -rf /var/lib/apt/lists/*

# Non-root user; sudo only for the firewall script, and only without arguments: `""` is sudoers' "no arguments"
# (backlog #0-283). The script used to add every argument to its allow-list, so `sudo init-firewall.sh <host>` let code
# in the container open any host (FAC-S02); the one host the owner's container needs comes from the image now (the
# ntfy server, below), never from the caller. The base image's uid 1000 is `ubuntu`, in the group `sudo` among others,
# and renaming it to `dev` kept them: `%sudo ALL=(ALL:ALL) ALL` needs a password, which `dev` does not have (locked),
# but one set later, or a NOPASSWD rule for the group, would give `dev` every command. So `dev` leaves `sudo`, and
# `admin`, the other group /etc/sudoers grants every command to, should a base image put it there (found by #0-283's
# trial, 2026-11-21). `adm`, which reads logs and grants no command, stays. The container's main process still runs as root
# ("containerUser" in devcontainer.json, for the Docker socket proxy): see the comment there and #0-116.
RUN (getent group ${USER_GID} || groupadd --gid ${USER_GID} ${USERNAME}) \
    && (id -u ${USER_UID} >/dev/null 2>&1 && usermod -l ${USERNAME} -d /home/${USERNAME} -m $(id -nu ${USER_UID}) || useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}) \
    && for g in sudo admin; do if id -nG ${USERNAME} | tr ' ' '\n' | grep -qx "$g"; then gpasswd -d ${USERNAME} "$g"; fi; done \
    && echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh \"\"" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && visudo -cf /etc/sudoers.d/${USERNAME}

# Claude Code at claude-code.pin's version, from the manifest Anthropic signed, root's and read-only to `dev` in
# /usr/local/bin (backlog #0-249, #0-283, ADR-0065). It was `curl -fsSL https://claude.ai/install.sh | bash` as `dev`:
# whatever version was newest the day the image was built (two images, two versions: #0-248), into `dev`'s ~/.local,
# where code an agent ran could replace the binary of the next call (ADR-0064's residual). Before the firewall
# script's layer, so a change there does not download the binary again.
COPY claude-code.pin install-claude-code.sh /usr/local/share/claude-code/
COPY keys/ /usr/local/share/claude-code/keys/
RUN /usr/local/share/claude-code/install-claude-code.sh --pin /usr/local/share/claude-code/claude-code.pin \
        --keys /usr/local/share/claude-code/keys --into /usr/local/bin

COPY init-firewall.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/init-firewall.sh

# The dispatcher's credential proxy on the build VM (backlog #0-313), the one address and port a task container may reach
# besides the list: copied from .devcontainer/factory-proxy, which check-allowlists.sh holds equal to provision.sh's
# PROXY_ADDR and first PROXY_PORTS. A file of the image and not a build argument of task.json: the dispatcher's closed
# table of task.json's keys (ADR-0062 point 4) carries `build.dockerfile` and `build.context` only. So the owner's
# container gets the file too; on the Mac nothing listens there, and the rule it gives opens one address and port.
COPY factory-proxy /etc/factory-firewall/proxy
# Anthropic's hosts, the owner's container's only (backlog #0-313 AC7): a build argument devcontainer.json passes and
# task.json, holding no `build.args`, cannot. With it unset, as in every task container, the image holds no choice and
# the firewall opens no Anthropic host: a task's model calls go through the proxy alone. "1" or nothing; anything else
# fails the build rather than guess.
ARG FACTORY_ANTHROPIC=""
# The one extra host the firewall opens, from the image and never from the caller (backlog #0-283): the ntfy server
# of the owner's container, a build argument devcontainer.json takes from the host's FACTORY_NTFY_SERVER. Empty (the
# task container, as task.json passes none): no file, no extra host. A host, not a URL, is written: the scheme, any port and any path are cut, and anything but
# letters, digits, dots and hyphens, or one starting with a hyphen (it would reach `dig` as an option) or holding an empty label (`..`), fails the build. A server changed on the host takes a rebuild; until then
# notifications fail and the firewall still comes up (a host given as an argument and held by sudo would have failed
# the firewall itself on such a change, leaving the network open).
ARG FACTORY_NTFY_SERVER=""
RUN mkdir -p /etc/factory-firewall \
    && case "${FACTORY_ANTHROPIC}" in \
        1) printf 'yes\n' > /etc/factory-firewall/anthropic ;; \
        '') ;; \
        *) echo "FACTORY_ANTHROPIC '${FACTORY_ANTHROPIC}' is neither 1 nor empty" >&2; exit 1 ;; \
    esac \
    && if [ -n "${FACTORY_NTFY_SERVER}" ]; then \
        host=$(printf '%s' "${FACTORY_NTFY_SERVER}" | sed -E 's#^https?://##; s#[/:].*##') \
        && case "$host" in *[!A-Za-z0-9.-]*|-*|''|*..*) echo "FACTORY_NTFY_SERVER '${FACTORY_NTFY_SERVER}' has no valid host" >&2; exit 1 ;; esac \
        && printf '%s\n' "$host" > /etc/factory-firewall/extra-hosts; \
    fi \
    && chown -R root:root /etc/factory-firewall \
    && chmod -R go-w /etc/factory-firewall

# The workspace is the host's directory, mounted, and Docker Desktop can report it under another owner
# than `dev`: git then refuses every command there ("detected dubious ownership"), and gh, which asks git
# which repository it is in, fails after it (labels "missing", CI status unreadable: seen at the first
# preflight, 2026-10-09). One repository, one user in this container: trust it system-wide, so a rebuild
# keeps it (a --global setting lives in the container's home and is lost).
RUN git config --system --add safe.directory /workspace
# git push uses gh's login (the machine account's token, in the gh volume): the credential helper
# `gh auth setup-git` would write, but in the system config, as `setup-git` writes ~/.gitconfig, which a
# rebuild loses while the gh login survives (seen 2026-10-09: push then asked for a password). The empty
# entry clears any helper configured before it. It holds no secret: without a gh login, a push fails.
RUN git config --system --add credential.https://github.com.helper '' \
    && git config --system --add credential.https://github.com.helper '!/usr/bin/gh auth git-credential'

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# The mount points of the named volumes (devcontainer.json), created here as `dev`: Docker gives a new
# volume the owner of the directory it is mounted over, and one the image does not have is root's. Without
# this, ~/.m2 and ~/.config/gh were root-owned: Maven could not write its cache, gh could not store the login.
RUN mkdir -p /home/${USERNAME}/.m2 /home/${USERNAME}/.config/gh /home/${USERNAME}/.claude

# Claude Code updates nothing in the container: DISABLE_AUTOUPDATER stops the background check only, and
# `claude update` or `claude install` would still lay a newer version out under ~/.local; DISABLE_UPDATES blocks every
# path (Claude Code's setup documentation). ~/.local/bin is no longer put first on PATH: the installed binary is
# /usr/local/bin/claude (above), and a `claude` an agent left in ~/.local/bin must not shadow it. A bump is a change to
# claude-code.pin (docs/ai-factory.md "Pinned versions").
ENV DISABLE_AUTOUPDATER=1 \
    DISABLE_UPDATES=1
