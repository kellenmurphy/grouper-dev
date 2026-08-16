#!/usr/bin/env bash
# =============================================================================
# clone-grouper-src.sh
#
# Host-side provisioning of the Internet2/grouper source checkout. Run by
# devcontainer.json initializeCommand before the container builds, so the
# ../../grouper bind mount in docker-compose.yml always points at a real
# checkout instead of a Docker-created empty directory.
#
# Idempotent and non-destructive: an existing git checkout is left completely
# untouched — local branches and work in progress are never at risk.
#
# The full Grouper history is huge, so the clone is shallow: HEAD of a single
# release branch, no history. Deepen later if needed:
#   git fetch --unshallow        # full history
#   git fetch --deepen 100       # or just more of it
#
# Overrides (export before opening the dev container):
#   GROUPER_SRC_REPO    clone URL (default: https://github.com/Internet2/grouper.git)
#   GROUPER_SRC_BRANCH  branch    (default: GROUPER_7_BRANCH; 5/6 also exist upstream)
# =============================================================================

set -euo pipefail

REPO_URL="${GROUPER_SRC_REPO:-https://github.com/Internet2/grouper.git}"
BRANCH="${GROUPER_SRC_BRANCH:-GROUPER_7_BRANCH}"

# Sibling of the grouper-dev repo root, matching the ../../grouper bind mount
# in .devcontainer/docker-compose.yml.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$(cd "${SCRIPT_DIR}/../.." && pwd)/grouper"

if [ -d "${TARGET}/.git" ]; then
    echo "==> [clone-grouper-src] ${TARGET} is already a git checkout — leaving it alone."
    exit 0
fi

if [ -d "${TARGET}" ] && [ ! -w "${TARGET}" ]; then
    echo "ERROR: ${TARGET} exists but is not writable (likely a root-owned empty dir" >&2
    echo "       created by a container start before the source was cloned)." >&2
    echo "       Remove it (sudo rm -rf ${TARGET}) and reopen the dev container." >&2
    exit 1
fi

if [ -d "${TARGET}" ] && [ -n "$(ls -A "${TARGET}" 2>/dev/null)" ]; then
    echo "ERROR: ${TARGET} exists, is not empty, and is not a git repository." >&2
    echo "       Move it aside or delete it, then reopen the dev container." >&2
    exit 1
fi

echo "==> [clone-grouper-src] Shallow-cloning ${REPO_URL} (${BRANCH}, HEAD only) into ${TARGET}..."
git clone --depth 1 --single-branch --branch "${BRANCH}" "${REPO_URL}" "${TARGET}"
echo "==> [clone-grouper-src] Done. No history was fetched — run 'git fetch --unshallow' in ${TARGET} if you need blame/log depth."
