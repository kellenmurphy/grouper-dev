# Grouper Development Container
#
# Based on Eclipse Temurin JDK 17. grouper-parent/pom.xml on GROUPER_7_BRANCH
# declares maven.compiler.source/target 17, so 17 is the correct line. Verify
# against that pom before changing it.
#
# Distro suffix is Ubuntu 26.04 LTS (resolute), supported to 2031. Renovate's
# eclipse-temurin rule pins the major version but does not move the distro
# suffix, so that part is a deliberate manual bump. Fall back to 17-jdk-noble
# (24.04 LTS) if resolute ever causes trouble; both carry every package this
# image installs, including NodeSource's Node 24.
FROM eclipse-temurin:17-jdk-resolute

# GROUPER_HOME points to the core module so gsh.sh can build its classpath.
# CWD must be /workspace/grouper when invoking gsh.sh — isApiMvnHome() checks
# grouper/target/grouper-*.jar as a relative path from CWD.
ENV GROUPER_HOME=/workspace/grouper/grouper

# ── System tools ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        ant \
        curl \
        git \
        maven \
        postgresql-client \
        sudo \
        vim \
        wget \
    && rm -rf /var/lib/apt/lists/*

# ── Non-root user ─────────────────────────────────────────────────────────────
# The Claude Code VS Code extension's background helper processes fail under
# root (the CLI refuses --dangerously-skip-permissions as root), so the
# container runs as "vscode" with passwordless sudo for dev convenience.
#
# Ubuntu 24.04 and later ship a default "ubuntu" account already holding
# UID/GID 1000, so a plain `useradd --uid 1000` fails the build with "UID 1000
# is not unique". Rename that account instead of adding a second one: the dev
# user has to keep UID 1000 so bind-mounted repo files stay writable from inside
# the container. The else branch covers older bases (jammy and earlier) where
# 1000 is free.
RUN if getent passwd 1000 >/dev/null; then \
        existing_user="$(getent passwd 1000 | cut -d: -f1)" \
        && existing_group="$(getent group 1000 | cut -d: -f1)" \
        && usermod --login vscode --home /home/vscode --move-home "${existing_user}" \
        && groupmod --new-name vscode "${existing_group}" \
        && usermod --shell /bin/bash vscode ; \
    else \
        groupadd --gid 1000 vscode \
        && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash vscode ; \
    fi \
    && echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

# ── Tomcat 9 ──────────────────────────────────────────────────────────────────
# Grouper 5.x targets Tomcat 9. Pin to a specific version for reproducibility.
ARG TOMCAT_VERSION=9.0.120
ENV CATALINA_HOME=/opt/tomcat

RUN curl -fsSL \
        "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" \
    | tar -xzC /opt \
    && mv /opt/apache-tomcat-${TOMCAT_VERSION} ${CATALINA_HOME} \
    && chmod +x ${CATALINA_HOME}/bin/*.sh \
    && chown -R vscode:vscode ${CATALINA_HOME}

# ── Node.js 24 LTS + Claude Code ──────────────────────────────────────────────
# Node.js is required by Claude Code; v24 is the active LTS line.
# claude-code is pinned; Renovate bumps it (renovate.json) after a cooldown so
# a compromised release can't reach a rebuild on day one.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @anthropic-ai/claude-code@2.1.233

# The CLI self-updates at runtime by default, which would silently defeat the
# version pin above — updates arrive only via Renovate PR + image rebuild.
ENV DISABLE_AUTOUPDATER=1

# ── Tomcat users ──────────────────────────────────────────────────────────────
# Passwords are substituted at container startup by scripts/init-grouper.sh.
COPY tomcat-users.xml.template ${CATALINA_HOME}/conf/tomcat-users.xml.template

# ── JDWP debug agent ──────────────────────────────────────────────────────────
# address=*:5005 is required in Docker so the host can connect to the JVM.
# suspend=n means Tomcat starts immediately without waiting for a debugger to attach.
ENV CATALINA_OPTS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"

# ── Ports ─────────────────────────────────────────────────────────────────────
# 8080: Tomcat HTTP
# 5005: JDWP remote debug
EXPOSE 8080 5005

# ── Directories owned by vscode ───────────────────────────────────────────────
# Pre-create the mount points so fresh named volumes inherit vscode ownership
# instead of defaulting to root.
RUN mkdir -p /workspace /home/vscode/.m2 /home/vscode/.claude \
    && chown -R vscode:vscode /workspace /home/vscode/.m2 /home/vscode/.claude

# ── Maven local repo ──────────────────────────────────────────────────────────
# Persisted as a named Docker volume to avoid re-downloading deps on rebuild.
VOLUME /home/vscode/.m2

WORKDIR /workspace

# Dev containers keep the container alive; VSCode manages the lifecycle.
CMD ["sleep", "infinity"]

USER vscode
