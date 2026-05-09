# Grouper Development Container
#
# Based on Eclipse Temurin JDK 17. Grouper 5.x / 6.x requires Java 17.
# Verify against grouper-parent/pom.xml -> java.version if in doubt.
FROM eclipse-temurin:17-jdk-jammy

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
        vim \
        wget \
    && rm -rf /var/lib/apt/lists/*

# ── Tomcat 9 ──────────────────────────────────────────────────────────────────
# Grouper 5.x targets Tomcat 9. Pin to a specific version for reproducibility.
ARG TOMCAT_VERSION=9.0.87
ENV CATALINA_HOME=/opt/tomcat

RUN curl -fsSL \
        "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" \
    | tar -xzC /opt \
    && mv /opt/apache-tomcat-${TOMCAT_VERSION} ${CATALINA_HOME} \
    && chmod +x ${CATALINA_HOME}/bin/*.sh

# ── Node.js 20 LTS + Claude Code ──────────────────────────────────────────────
# Node.js 20.12.0+ is required by Claude Code.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @anthropic-ai/claude-code

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

# ── Maven local repo ──────────────────────────────────────────────────────────
# Persisted as a named Docker volume to avoid re-downloading deps on rebuild.
VOLUME /root/.m2

WORKDIR /workspace

# Dev containers keep the container alive; VSCode manages the lifecycle.
CMD ["sleep", "infinity"]
