# Grouper Dev Environment

A VSCode Dev Container setup for Grouper source development and upstream contribution.
Provides a fully containerized environment with Java, Maven, Tomcat, PostgreSQL,
and Claude Code — no local Java or build tooling required.

## Repo layout

This repo (`grouper-dev`) lives alongside the [`Internet2/grouper`](https://github.com/Internet2/grouper) source repo as siblings:

```
~/repos/
├── grouper-dev/       ← this repo (dev environment config)
│   ├── .devcontainer/ ← Docker + VSCode Dev Container config
│   ├── .vscode/       ← tasks, launch configs, editor settings
│   ├── conf/          ← static Grouper config files (tracked here, symlinked into grouper/conf/)
│   ├── maven/         ← settings.xml (mirrors broken Sonatype repo → Maven Central)
│   ├── tomcat/        ← Tomcat JVM settings (setenv.sh, symlinked into $CATALINA_HOME/bin/)
│   ├── scripts/       ← init-grouper.sh (container creation), clone-grouper-src.sh (host, pre-build)
│   ├── grouper.code-workspace  ← open this inside the container for both repos
│   ├── CLAUDE.md      ← Claude Code context (auto-read by claude CLI)
│   └── README.md      ← this file
└── grouper/           ← Internet2/grouper source (separate git repo)
```

## What's in the container

| Component | Version | Purpose |
|-----------|---------|---------|
| Eclipse Temurin JDK | 17 | Java runtime and compiler |
| Maven | 3.x | Primary build tool |
| Tomcat | 9.x (pinned in Dockerfile) | Servlet container with JDWP debug agent |
| PostgreSQL client | 16 | DB admin from container terminal |
| Node.js | 24 LTS | Required by Claude Code |
| Claude Code | pinned in Dockerfile, Renovate-managed | AI coding assistant (CLI + VSCode extension) |

## Prerequisites

**WSL2 (Windows)**
- `docker-ce` installed and running in WSL2 — no Docker Desktop required
- Current user in the `docker` group: `sudo usermod -aG docker $USER`
- VSCode extensions installed on the Windows side:
  - `ms-vscode-remote.remote-wsl`
  - `ms-vscode-remote.remote-containers`

**Mac**
- OrbStack (recommended — lighter than Docker Desktop, native ARM64) or Docker Desktop:

  ```bash
  brew install orbstack          # or: brew install --cask docker
  ```

- VSCode with the Dev Containers extension:

  ```bash
  brew install --cask visual-studio-code
  code --install-extension ms-vscode-remote.remote-containers
  ```

## Getting started

### 1. Clone this repo

```bash
cd ~/repos
git clone <this-repo-url> grouper-dev
```

The Grouper source itself is provisioned automatically: on container open, `scripts/clone-grouper-src.sh` runs on the host and shallow-clones the HEAD of `GROUPER_7_BRANCH` from `Internet2/grouper` into the sibling `grouper/` directory (no history — the full repo is huge). An existing checkout there is never touched. To use a different branch or your fork, export `GROUPER_SRC_BRANCH` / `GROUPER_SRC_REPO` before opening the container. If you later need blame or log depth, run `git fetch --unshallow` inside the checkout.

### 2. Open in VSCode

**Windows** — run (or create a desktop shortcut for this):

```
wsl.exe -d Ubuntu -e bash -c "code ~/repos/grouper-dev"
```

VSCode opens in WSL mode.

**Mac** — from a terminal (make sure the Docker engine is running first):

```bash
code ~/repos/grouper-dev
```

Either way, VSCode prompts: **"Reopen in Container"** — click it.
Alternatively use **F1 → Dev Containers: Reopen in Container**.

The first build takes several minutes (pulling the base image, installing
Node.js, downloading Tomcat). Subsequent opens are fast — the image is cached.

### 3. Open the workspace file (first time only)

Once inside the container, open the workspace file to get both repos in the sidebar:

```
File → Open Workspace from File → /workspace/grouper-dev/grouper.code-workspace
```

VSCode remembers this for all future container attaches — you only do this once.

### 4. Build Grouper

```
Ctrl+Shift+B (Cmd+Shift+B on Mac)  →  Maven: Build All (skip tests)
```

First run downloads the entire Maven dependency tree — this takes a while.
Grab a coffee. The `~/.m2` cache is persisted in a Docker volume so subsequent
builds are much faster. The task runs with `-U` so transient download failures
on first run are automatically retried.

### 5. Initialize and run

```
Terminal → Run Task → Deploy: UI to Tomcat
Terminal → Run Task → GSH: Init Registry
F5  →  Start Tomcat + Attach Debugger
```

Browse to `http://localhost:8080/grouper` and log in with `GrouperSystem` / `changeme`
(or whatever you set `GROUPER_SYSTEM_PASSWORD` to in your `.env`).

> The registry init and UI password are handled automatically by `init-grouper.sh` on container
> creation if the build already exists. On a fresh clone you always need to build first (step 4),
> then run **GSH: Init Registry** once.

## Typical dev loop

| What you changed | What to do |
|-----------------|-----------|
| Java method body only | Run → Apply Code Changes — no restart needed |
| Java structure (new methods/fields) | `Maven: Build API only` → `Tomcat: Restart` |
| UI templates / Groovy views | `Deploy: UI to Tomcat` — Tomcat may hot-reload |
| WS changes | `Maven: Build WS only` → `Deploy: WS to Tomcat` → `Tomcat: Restart` |
| Config files in `grouper-dev/conf/` | Edit in place → `Tomcat: Restart` (symlinks pick up changes immediately) |

## Debugging

**F5** launches the compound config: starts Tomcat in a background terminal,
waits for the startup message, then attaches the JDWP debugger. Set breakpoints
anywhere in the Grouper source — they're live immediately.

Hot Code Replacement works for method body changes without a restart. Structural
changes (new methods, fields, classes) require a rebuild and restart.

## Claude Code

The `claude` CLI and VSCode extension are installed in the container. On first use,
authenticate with your Anthropic account when prompted. Credentials are stored in
`~/.claude/` inside the container and persisted in the `claude-auth` Docker volume —
they survive container rebuilds and are never written to either git repo.

The `CLAUDE.md` file in this repo is read automatically by Claude Code on every
invocation, providing project context without re-explaining the setup each session.

## DBeaver connection

PostgreSQL is exposed on your host at `localhost:5432`.

| Setting | Value |
|---------|-------|
| Host | `localhost` |
| Port | `5432` |
| Database | `grouper` |
| Username | `grouper` |
| Password | `grouper` (or whatever's in your `.env`) |
| Driver | PostgreSQL |

## Volumes

Three named Docker volumes persist data across container rebuilds:

| Volume | Contents |
|--------|----------|
| `maven-cache` | Maven local repository (`~/.m2`) |
| `postgres-data` | PostgreSQL database files |
| `claude-auth` | Claude Code authentication (`~/.claude`) |

To reset any of these: `docker volume rm <project-name>_<volume-name>`

## Configuration files

Grouper's user-managed config files live in `grouper-dev/conf/` and are version-controlled here.
On container creation, `init-grouper.sh` symlinks them into `grouper/conf/` so both GSH and the
build find them. The deploy task copies `grouper/conf/` (following symlinks) into the webapp's
`WEB-INF/classes/` so Tomcat's class loader picks them up.

| File | Purpose |
|------|---------|
| `conf/grouper.properties` | Core Grouper settings |
| `conf/grouper.cache.properties` | Cache configuration |
| `conf/subject.properties` | Subject source definitions |
| `conf/morphString.properties` | String encryption key (dev only — do not use in prod) |
| `conf/log4j2.xml` | Logging configuration |
| `tomcat/setenv.sh` | JVM args for Tomcat: `--add-opens` flags and log4j config pointer |
| `maven/settings.xml` | Maven mirror: routes broken Sonatype `nexus-releases` URL → Maven Central |
| `maven/lifecycle-mapping-metadata.xml` | m2e lifecycle override: prevents `maven-resources-plugin:3.3.1` from executing during IDE incremental builds (avoids ~15K `ClassNotFoundException` errors in Problems panel) |

One file is **generated** (not tracked): `grouper/conf/grouper.hibernate.properties`.
It is written by `init-grouper.sh` at container creation using the DB credentials from
environment variables. Edit `scripts/init-grouper.sh` if you need to change those settings.

**Authentication:** the UI uses Grouper's built-in HTTP Basic auth (`grouper.is.ui.basicAuthn = true`).
Credentials are stored in the `grouper_password` database table, not in `tomcat-users.xml`.
`init-grouper.sh` creates the `GrouperSystem` UI password automatically using the
`GROUPER_SYSTEM_PASSWORD` env var (default: `changeme`).

**GSH headless:** when running GSH non-interactively (scripts, `init-grouper.sh`), pass
`GROUPER_GSH_JVMARGS=-Djava.awt.headless=true` to avoid an AWT/X11 library error.

## Customizing credentials

Create a `.env` file in `grouper-dev/.devcontainer/` to override defaults without
committing secrets (`.env` is git-ignored):

```env
GROUPER_SYSTEM_PASSWORD=yoursecretpassword
TEST_SUBJECT_PASSWORD=yoursecretpassword
POSTGRES_PASSWORD=yourdbpassword
DB_PASSWORD=yourdbpassword
# Optional: skip interactive Claude sign-in entirely (mint with `claude setup-token`).
# Per-person credential — never commit or share it. Interactive sign-in already
# persists in the claude-auth volume, so most people can omit this.
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat...
```

## Checkstyle

Configured automatically to use `grouper/grouper-parent/src/checkstyle/checkstyle.xml`.
Runs in the background as you edit. For new upstream contribution code use
`checkstyle.xml`; for older files with pre-existing violations switch to
`checkstyle-legacy.xml` in `.vscode/settings.json`.

The version is pinned to `8.23` — Grouper's config is incompatible with higher versions.

## Java version

The container uses JDK 17 (`eclipse-temurin:17-jdk-jammy`), matching the
`maven.compiler.source` in `grouper-parent/pom.xml`.


## Mac notes

On Apple Silicon, `eclipse-temurin` has native ARM64 builds — no Rosetta emulation.
No WSL-specific steps needed; just open the `grouper-dev` folder directly in VSCode
and reopen in container when prompted.

Keybindings map as usual: `Ctrl+Shift+B` → `Cmd+Shift+B`, and `F5` may need `fn+F5` depending on your function-key settings. Everything inside the container (tasks, launch configs, paths) is identical on both platforms.
