# Grouper Dev Environment — Claude Code Context

This file is read automatically by Claude Code. It describes the dev environment
setup task, the file layout, assumptions that need verification, and the overall
goal of the work.

---

## What this is

We are setting up a VSCode Dev Container development environment for the
[Internet2 Grouper](https://github.com/Internet2/grouper) IAM platform. The goal
is a fully containerized local dev environment that supports editing Grouper source
code, building with Maven/Ant, debugging via JDWP, and running the Grouper UI and
WS against a local PostgreSQL database — suitable for upstream contribution work.

This is **not** a deployment setup. We are building in the source, not using the
pre-built `i2incommon/grouper` Docker image.

---

## Target file layout

These files drop into the root of the cloned Grouper source repository
(`https://github.com/Internet2/grouper`). The repo root contains `grouper-parent/`
which is the Maven multi-module project.

```
grouper/                          ← repo root (also the VS Code workspace root)
├── .devcontainer/
│   ├── Dockerfile                ← JDK + Maven + Ant + Tomcat dev image
│   ├── docker-compose.yml        ← grouper-dev service + PostgreSQL service
│   ├── devcontainer.json         ← VSCode Dev Containers config
│   ├── tomcat-users.xml.template ← Tomcat user config (passwords injected at runtime)
│   └── initdb/
│       └── .gitkeep              ← Drop *.sql init scripts here if needed
├── .vscode/
│   ├── tasks.json                ← Build, deploy, Tomcat, GSH tasks
│   ├── launch.json               ← JDWP attach + F5 start-and-attach config
│   ├── extensions.json           ← Recommended extensions
│   └── settings.json             ← Java, Checkstyle, editor settings
├── .editorconfig                 ← Coding standards (2-space Java indent, LF, 200 char)
├── scripts/
│   ├── init-grouper.sh           ← First-time setup: waits for DB, writes properties,
│   │                                inits Grouper registry, sets the GrouperSystem UI
│   │                                password. Run by postCreateCommand and by the
│   │                                "Grouper: Init Registry + UI Password" task.
│   ├── clone-grouper-src.sh      ← Host-side shallow clone of Internet2/grouper.
│   │                                Run by initializeCommand.
│   ├── start-tomcat.sh           ← Starts Tomcat detached, blocks until JDWP 5005 is
│   │                                accepting. preLaunchTask for the F5 config.
│   └── stop-tomcat.sh            ← Stops Tomcat, blocks until the ports release.
├── CLAUDE.md                     ← This file
└── grouper-parent/               ← Existing Maven multi-module source (do not modify
                                     structure)
```

---

## Things to verify before running

These are assumptions baked into the config files that may need adjustment based on
the actual state of the repo. Check these first.

### 1. Java version

Check `grouper-parent/pom.xml` for the `<java.version>` property (or
`<maven.compiler.source>`). The Dockerfile uses `eclipse-temurin:17-jdk-resolute`
(Ubuntu 26.04 LTS). GROUPER_7_BRANCH declares `maven.compiler.source/target` 17,
so the 17 line is correct. If the pom ever moves to a different Java version,
change the FROM line accordingly. Renovate pins the major version but will not
move the distro suffix, so that is a manual bump.

### 2. Tomcat version

The Dockerfile installs a pinned Tomcat 9.x (see TOMCAT_VERSION in the Dockerfile;
Renovate keeps it current within 9.x). Verify this is consistent with what Grouper
expects by checking the `i2incommon/grouper` Dockerfile in the upstream repo or the
`grouper-parent/grouper-ui/build.xml` for any Tomcat version references.

### 3. GSH binary path

`scripts/init-grouper.sh` and `.vscode/tasks.json` reference:
```
grouper-parent/grouper/bin/gsh.sh
```
Confirm this path exists after a Maven build. If the binary is elsewhere or named
differently, update both files.

### 4. UI webapp source path

`.vscode/tasks.json` references:
```
grouper-parent/grouper-ui/WebContent
```
for the `Deploy: UI to Tomcat` task. Verify this is the correct webapp root for the
UI module. It may be `src/main/webapp` in newer Maven layouts.

### 5. WS webapp source path

Similarly, the WS deploy task references:
```
grouper-parent/grouper-ws/webapp
```
Verify against the actual repo.

### 6. Checkstyle config path

`.vscode/settings.json` points Checkstyle at:
```
grouper-parent/src/checkstyle/checkstyle.xml
```
Confirm this file exists at that path in the repo. The legacy version is at:
```
grouper-parent/src/checkstyle/checkstyle-legacy.xml
```

---

## Local machine setup (WSL2, no Docker Desktop)

The developer is on Windows using WSL2 with `docker-ce` (not Docker Desktop). The
Mac transition is coming within a month.

### WSL2 requirements
- `docker-ce` installed and the daemon running (`sudo service docker start` or
  systemd if enabled in WSL2)
- Current user in the `docker` group:
  ```bash
  sudo usermod -aG docker $USER
  # Log out and back in (or: newgrp docker)
  ```
- VSCode extensions installed on the Windows side:
  - `ms-vscode-remote.remote-wsl` (WSL extension)
  - `ms-vscode-remote.remote-containers` (Dev Containers)
- The Grouper repo must live in the WSL2 filesystem (`~/` etc.), **not** on
  `/mnt/c/...`. Maven build performance on mounted Windows drives is severely degraded.

### Workflow to open the dev container
1. Open VSCode on Windows
2. Click the remote indicator (bottom-left corner) → "Connect to WSL"
3. File → Open Folder → navigate to the Grouper repo inside WSL2
4. VSCode detects `.devcontainer/` and prompts "Reopen in Container" — click it
5. First build takes several minutes (base image + Maven deps download)

### Port access from Windows
Ports 8080 (Grouper UI), 5005 (JDWP), and 5432 (PostgreSQL/DBeaver) are all exposed in
`docker-compose.yml` and are accessible from Windows at `localhost:<port>` via WSL2's
automatic port forwarding. No additional configuration needed.

### DBeaver connection (from Windows)
| Setting  | Value       |
|----------|-------------|
| Host     | `localhost` |
| Port     | `5432`      |
| Database | `grouper`   |
| User     | `grouper`   |
| Password | `grouper`   |
| Driver   | PostgreSQL  |

In DBeaver's Driver Properties, set:

---

## Development workflow summary

### First time (fresh clone)
```
1. Ctrl+Shift+B → "Maven: Build All (skip tests)"   # ~10-20 min first run
2. Task: "Deploy: UI to Tomcat"
3. Task: "Grouper: Init Registry + UI Password"     # required; see note below
4. F5 → "Start Tomcat + Attach Debugger"
5. Browse http://localhost:8080/grouper
```

Step 3 is not optional on a fresh clone. `postCreateCommand` runs `init-grouper.sh`
before any build exists, so it skips the registry init and the `GrouperSystem`
password. The task re-runs the same script against the completed build, creating
the schema and the `grouper_password` row. Skip it and the UI 401s on every login,
including the documented default. The script is idempotent.

### Ongoing
```
After changing Java source (method body):  Run > Apply Code Changes (no restart)
After changing Java source (structure):    Maven: Build API only → Deploy → Tomcat: Restart
After changing UI templates:               Deploy: UI to Tomcat (Tomcat may hot-reload)
After changing WS:                         Maven: Build WS only → Deploy: WS to Tomcat → Restart
```

### Debugging
- **F5** runs the `Tomcat: Start` task (which blocks until port 5005 accepts and
  the UI answers) and then attaches JDWP. Tomcat runs detached; use
  `Tomcat: Tail Logs` for its console, or `Tomcat: Start (foreground console)`
  plus `Attach to Tomcat (JDWP)` to keep the log in the terminal
- Tomcat is launched under `setsid`, in its own session, so VS Code's task
  process-group teardown cannot SIGTERM it out from under the attaching
  debugger. It therefore outlives the terminal: stop it with `Tomcat: Stop`
- Breakpoints work in any Java file under `grouper-parent/`
- For GSH script debugging, use the "Debug GSH Script" launch config
- For JUnit test debugging, use the "Debug JUnit Test" launch config or right-click
  a test file → Run/Debug

---

## Credentials and secrets

Default credentials are intentionally weak and for local dev only. To override without
committing secrets, create a `.env` file next to `docker-compose.yml`:

```env
GROUPER_SYSTEM_PASSWORD=yoursecretpassword
TEST_SUBJECT_PASSWORD=yoursecretpassword
DB_PASSWORD=yourdbpassword
```

`DB_PASSWORD` drives both the app and the postgres service, so there is no separate
`POSTGRES_PASSWORD` to keep in sync. Every value in the compose `environment:` blocks
must stay in `${VAR:-default}` form: a bare literal there wins over `.env` and ignores
the override silently.

Neither override is retroactive. `GROUPER_SYSTEM_PASSWORD` is read only when
`init-grouper.sh` runs, and `DB_PASSWORD` only when PostgreSQL initialises an empty
data directory. Changing either after the fact requires re-running the init task or
dropping the `postgres-data` volume.

`.env` is in `.gitignore`. Do not commit it.

---

## Mac transition notes

When moving to Mac, the only change needed is Docker Desktop or OrbStack (OrbStack
is recommended — faster, lighter, native ARM64). The dev container config is
identical. The WSL2-specific workflow above is replaced by simply opening the folder
in VSCode normally (no WSL extension needed on Mac).

---

## Upstream contribution context

This developer is contributing features upstream to Internet2/grouper. Keep this
in mind when suggesting code changes:

- Follow the Grouper coding standards: 2-space Java indent, LF line endings,
  200-char hard wrap, no wildcard imports
- Checkstyle must pass with `checkstyle.xml` (not the legacy variant) for new code
- Copyright header is required on new Java files (Apache 2.0, Internet2)
- The Grouper project uses both Maven and Ant; prefer Maven for builds but Ant
  tasks (`ant dev`) are still required for dev lib setup in UI and WS modules

---

## Out of scope (for now)

- Refactoring the existing Docker Swarm DEV/QA/PROD deployment
- Multi-engineer shared dev environments
- HotswapAgent / DCEVM for enhanced hot code replacement
- LDAP container for subject source testing (can be added later)
