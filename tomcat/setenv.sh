#!/usr/bin/env bash
# Grouper-specific JVM settings for Tomcat.
# Sourced automatically by catalina.sh before startup — do not invoke directly.
#
# JDWP and memory settings live in CATALINA_OPTS in the Dockerfile so they're
# visible as container config. This file holds Grouper's Java 17 module opens
# and the log4j2 config pointer.

CATALINA_OPTS="$CATALINA_OPTS --add-opens=java.sql/java.sql=ALL-UNNAMED"
CATALINA_OPTS="$CATALINA_OPTS --add-opens=java.base/java.nio=ALL-UNNAMED"
CATALINA_OPTS="$CATALINA_OPTS -Dlog4j.configurationFile=${CATALINA_HOME}/conf/log4j2.xml"
export CATALINA_OPTS
