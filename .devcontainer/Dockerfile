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

# Non-root user; sudo only for the firewall script. The container's main process still runs as root
# ("containerUser" in devcontainer.json, for the Docker socket proxy): see the comment there and #0-116.
RUN (getent group ${USER_GID} || groupadd --gid ${USER_GID} ${USERNAME}) \
    && (id -u ${USER_UID} >/dev/null 2>&1 && usermod -l ${USERNAME} -d /home/${USERNAME} -m $(id -nu ${USER_UID}) || useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}) \
    && echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

COPY init-firewall.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/init-firewall.sh

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

# Claude Code, native installer. Updates are off in the container (DISABLE_AUTOUPDATER): the version the
# autopilot runs is the one this image was built with — rebuild the image to upgrade, then run the
# seed-bugs benchmark before trusting the new version (docs/ai-factory.md, "Pinned versions").
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}" \
    DISABLE_AUTOUPDATER=1
