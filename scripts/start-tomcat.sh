#!/usr/bin/env bash
# =============================================================================
# start-tomcat.sh
#
# Starts Tomcat and does not return until the JDWP port is actually accepting,
# then exits 0. This is the preLaunchTask for the "Start Tomcat + Attach
# Debugger" launch config.
#
# Why a script instead of a background task + problemMatcher: VS Code decides a
# background task is "ready" by scraping its output with a problemMatcher, which
# has to stay in sync with Tomcat's log format and has to satisfy VS Code's
# pattern validator. When any of that is off, the debugger attaches before the
# JVM is listening and fails with "Failed to attach to localhost:5005 (attach
# timeout 30000)". A plain task that exits when the port is ready has no such
# ambiguity: VS Code just waits for the process to exit.
#
# Tomcat is started detached, so its console goes to $CATALINA_HOME/logs/
# catalina.out. Use the "Tomcat: Tail Logs" task to watch it, or the
# "Tomcat: Start (foreground console)" task if you want it in the terminal.
#
# Idempotent: if something is already listening on the debug port, this exits 0
# without starting a second instance.
# =============================================================================

set -euo pipefail

DEBUG_PORT="${DEBUG_PORT:-5005}"
HTTP_PORT="${HTTP_PORT:-8080}"
WAIT_SECONDS="${WAIT_SECONDS:-90}"
CATALINA_OUT="${CATALINA_HOME}/logs/catalina.out"

port_open() {
    (timeout 1 bash -c "</dev/tcp/localhost/$1") >/dev/null 2>&1
}

if port_open "${DEBUG_PORT}"; then
    echo "==> [start-tomcat] Port ${DEBUG_PORT} is already accepting; Tomcat looks to be running."
    echo "    Nothing to do. Run \"Tomcat: Stop\" first if you meant to restart it."
    exit 0
fi

if port_open "${HTTP_PORT}"; then
    echo "ERROR: port ${HTTP_PORT} is in use but the debug port ${DEBUG_PORT} is not." >&2
    echo "       Something other than this dev Tomcat is holding the HTTP port." >&2
    exit 1
fi

echo "==> [start-tomcat] Starting Tomcat (detached)..."
# setsid is load-bearing, not decoration.
#
# VS Code kills a task's entire process group once the task exits. catalina.sh
# start backgrounds the JVM but leaves it in the caller's process group, so the
# sequence was: this script exits 0 -> VS Code reaps the group -> the JVM takes
# SIGTERM and runs its shutdown hook -> the debugger attaches to a dead port and
# fails with "attach timeout 30000". In catalina.out that looked like "Server
# startup in [3708] milliseconds" followed 93ms later by Thread-14 shutting the
# connectors down.
#
# setsid puts Tomcat in its own session and process group, so the task teardown
# cannot reach it. It outlives the terminal, which is the point: the debugger
# attaches after this script returns.
#
# Consequence: Tomcat is no longer tied to the task's lifetime, so it must be
# stopped explicitly with "Tomcat: Stop".
setsid nohup "${CATALINA_HOME}/bin/catalina.sh" start </dev/null >/dev/null 2>&1

echo "==> [start-tomcat] Waiting up to ${WAIT_SECONDS}s for the debug port ${DEBUG_PORT}..."
for (( i = 0; i < WAIT_SECONDS; i++ )); do
    if port_open "${DEBUG_PORT}"; then
        echo "    Debug port ${DEBUG_PORT} is accepting after ${i}s."

        # JDWP is all the debugger needs, so from here on nothing is fatal.
        # Tomcat binds the HTTP connector during init, well before the webapps
        # finish deploying, so a TCP connect to 8080 is not a readiness signal.
        # Poll for a real HTTP status from /grouper instead, and just report if
        # it never comes: on a container where the UI has not been deployed yet
        # it never will, and that is not a reason to refuse to attach.
        for (( j = i; j < WAIT_SECONDS; j++ )); do
            CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 \
                     "http://localhost:${HTTP_PORT}/grouper/" 2>/dev/null || echo "000")
            case "${CODE}" in
                200|401|403)
                    echo "    Grouper UI responding (HTTP ${CODE}) after ${j}s."
                    echo "==> [start-tomcat] Tomcat is up. Attaching debugger."
                    exit 0
                    ;;
            esac
            sleep 1
        done

        echo "    NOTE: the debugger can attach, but /grouper never returned a"
        echo "          login response within ${WAIT_SECONDS}s (last status: ${CODE:-none})."
        echo "          If you have not run \"Deploy: UI to Tomcat\" yet, that is expected."
        echo "==> [start-tomcat] Tomcat is up. Attaching debugger."
        exit 0
    fi
    sleep 1
done

echo "" >&2
echo "ERROR: Tomcat did not come up within ${WAIT_SECONDS}s." >&2
if [ -f "${CATALINA_OUT}" ]; then
    echo "       Last 40 lines of ${CATALINA_OUT}:" >&2
    tail -40 "${CATALINA_OUT}" >&2
else
    echo "       No ${CATALINA_OUT} to show." >&2
fi
exit 1
