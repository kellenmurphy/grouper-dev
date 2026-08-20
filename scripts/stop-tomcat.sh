#!/usr/bin/env bash
# =============================================================================
# stop-tomcat.sh
#
# Stops Tomcat and does not return until the ports are actually released.
#
# catalina.sh stop returns as soon as it has sent the shutdown command, not when
# the JVM has exited. Returning early makes "Tomcat: Restart" race itself: the
# start half runs while the old JVM still holds 8080, the new one fails to bind,
# and the debug port never appears.
#
# Idempotent: exits 0 if Tomcat is already stopped.
# =============================================================================

set -euo pipefail

DEBUG_PORT="${DEBUG_PORT:-5005}"
HTTP_PORT="${HTTP_PORT:-8080}"
WAIT_SECONDS="${WAIT_SECONDS:-60}"

port_open() {
    (timeout 1 bash -c "</dev/tcp/localhost/$1") >/dev/null 2>&1
}

if ! port_open "${DEBUG_PORT}" && ! port_open "${HTTP_PORT}"; then
    echo "==> [stop-tomcat] Tomcat is not running. Nothing to do."
    exit 0
fi

echo "==> [stop-tomcat] Sending shutdown..."
# Tomcat started from the foreground task has no shutdown port owner issues, but
# a JVM that never finished booting will refuse the shutdown command. Don't let
# that abort the script: fall through to the SIGTERM path below.
"${CATALINA_HOME}/bin/catalina.sh" stop 2>&1 || echo "    (shutdown command failed; will fall back to signalling the process)"

echo "==> [stop-tomcat] Waiting up to ${WAIT_SECONDS}s for ports to release..."
for (( i = 0; i < WAIT_SECONDS; i++ )); do
    if ! port_open "${DEBUG_PORT}" && ! port_open "${HTTP_PORT}"; then
        echo "    Tomcat stopped after ${i}s."
        exit 0
    fi
    # Half way through, escalate to SIGTERM on the Bootstrap process.
    if [ "${i}" -eq $(( WAIT_SECONDS / 2 )) ]; then
        PIDS=$(pgrep -f "org.apache.catalina.startup.Bootstrap" || true)
        if [ -n "${PIDS}" ]; then
            echo "    Still up; sending SIGTERM to: ${PIDS}"
            # shellcheck disable=SC2086
            kill ${PIDS} 2>/dev/null || true
        fi
    fi
    sleep 1
done

echo "" >&2
echo "ERROR: Tomcat still holding a port after ${WAIT_SECONDS}s." >&2
pgrep -af "org.apache.catalina.startup.Bootstrap" >&2 || true
exit 1
