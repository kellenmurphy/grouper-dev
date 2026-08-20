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
Terminal → Run Task → Grouper: Init Registry + UI Password
F5  →  Start Tomcat + Attach Debugger
```

Browse to `http://localhost:8080/grouper` and log in with `GrouperSystem` / `changeme` (or whatever you set `GROUPER_SYSTEM_PASSWORD` to in your `.env`).

> **Do not skip the Init Registry task on a fresh clone.** `postCreateCommand` runs `init-grouper.sh` before any build exists, so on first container creation the script skips both the registry init and the `GrouperSystem` password, and says so in its output. The task above re-runs the same script now that the build is there, which is what creates the schema and the `grouper_password` row the UI authenticates against. Without it the UI returns 401 for every login, including the documented default. The task is idempotent, so re-run it any time.

## Typical dev loop

| What you changed | What to do |
|-----------------|-----------|
| Java method body only | Run → Apply Code Changes — no restart needed |
| Java structure (new methods/fields) | `Maven: Build API only` → `Tomcat: Restart` |
| UI templates / Groovy views | `Deploy: UI to Tomcat` — Tomcat may hot-reload |
| WS changes | `Maven: Build WS only` → `Deploy: WS to Tomcat` → `Tomcat: Restart` |
| Config files in `grouper-dev/conf/` | Edit in place → `Tomcat: Restart` (symlinks pick up changes immediately) |

## Debugging

**F5** runs the `Tomcat: Start` task and then attaches the JDWP debugger. That task starts Tomcat detached and blocks until port 5005 is accepting and the UI answers, so the debugger never attaches to a JVM that is not listening yet. Set breakpoints anywhere in the Grouper source, they are live immediately.

Because Tomcat is detached, its console goes to `$CATALINA_HOME/logs/catalina.out`. Run **Tomcat: Tail Logs** to watch it, or use **Tomcat: Start (foreground console)** when you would rather have the log in the terminal and attach separately with **Attach to Tomcat (JDWP)**.

Tomcat is started with `setsid`, in its own session, so it deliberately outlives the task terminal that launched it. VS Code kills a task's process group when the task exits, and without this the JVM was taking SIGTERM and shutting down a fraction of a second before the debugger attached. The trade-off is that closing the terminal no longer stops Tomcat: use **Tomcat: Stop**, which waits for the ports to release.

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
| Password | `grouper` (or whatever you set `DB_PASSWORD` to in your `.env`) |
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

**Authentication:** the UI uses Grouper's built-in HTTP Basic auth (`grouper.is.ui.basicAuthn = true`). Credentials live in the `grouper_password` database table, not in `tomcat-users.xml`, so `tomcat-users.xml` has no bearing on whether a UI login works. `init-grouper.sh` writes the `GrouperSystem` row from the `GROUPER_SYSTEM_PASSWORD` env var (default: `changeme`), but only on a run where the Maven build already exists. If the UI 401s on a password you believe is correct, that row is the first thing to check:

```sql
select username, application, encryption_type from grouper_password;
```

An empty result means `init-grouper.sh` has not yet run against a completed build. Run the **Grouper: Init Registry + UI Password** task and try again.

**GSH headless:** GSH needs `GROUPER_GSH_JVMARGS=-Djava.awt.headless=true` anywhere there is no DISPLAY, which includes VS Code task terminals as well as `postCreateCommand`. `gsh.sh` only passes the variable through and never sets headless itself, so omitting it produces an AWT/X11 library error. The tasks and `init-grouper.sh` set it already; add it to any GSH command you run by hand.

## Customizing credentials

Create a `.env` file in `grouper-dev/.devcontainer/` to override defaults without committing secrets (`.env` is git-ignored):

```env
GROUPER_SYSTEM_PASSWORD=yoursecretpassword
TEST_SUBJECT_PASSWORD=yoursecretpassword
# Sets the password on both the app and the postgres service; there is no
# separate POSTGRES_PASSWORD knob, so the two can never drift apart.
DB_PASSWORD=yourdbpassword
# Optional: skip interactive Claude sign-in entirely (mint with `claude setup-token`).
# Per-person credential — never commit or share it. Interactive sign-in already
# persists in the claude-auth volume, so most people can omit this.
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat...
```

Two things to know about when these take effect:

`GROUPER_SYSTEM_PASSWORD` is only read when `init-grouper.sh` runs. Changing it in `.env` does not rewrite an existing `grouper_password` row, so rebuild the container or run the **Grouper: Init Registry + UI Password** task afterwards.

`DB_PASSWORD` is only applied when PostgreSQL initialises an empty data directory. Once the `postgres-data` volume exists, changing it in `.env` leaves the database password as it was and breaks the connection instead of updating it. Either set it before you first start the stack, or drop the volume (`docker volume rm <project-name>_postgres-data`, which destroys the registry) and re-init.

## Checkstyle

Configured automatically to use `grouper/grouper-parent/src/checkstyle/checkstyle.xml`.
Runs in the background as you edit. For new upstream contribution code use
`checkstyle.xml`; for older files with pre-existing violations switch to
`checkstyle-legacy.xml` in `.vscode/settings.json`.

The version is pinned to `8.23` — Grouper's config is incompatible with higher versions.

## Java version

The container uses JDK 17 (`eclipse-temurin:17-jdk-resolute`, Ubuntu 26.04 LTS), matching the
`maven.compiler.source` in `grouper-parent/pom.xml`.


## Mac notes

On Apple Silicon, `eclipse-temurin` has native ARM64 builds — no Rosetta emulation.
No WSL-specific steps needed; just open the `grouper-dev` folder directly in VSCode
and reopen in container when prompted.

Keybindings map as usual: `Ctrl+Shift+B` → `Cmd+Shift+B`, and `F5` may need `fn+F5` depending on your function-key settings. Everything inside the container (tasks, launch configs, paths) is identical on both platforms.
