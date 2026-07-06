# 📁 Drive Auto-Fetcher

A background service that watches a Google Drive folder — or your entire Drive —
downloads every file to a folder on your machine with the **exact same folder
structure**, and **deletes each file from Drive** the moment it finishes
downloading. New files are detected on a configurable interval. Already-downloaded
files are never re-downloaded.

Managed by **PM2** — a process manager that keeps the script running 24/7 and
automatically restarts it on crashes or reboots.

Runs on **Windows, Linux, and macOS**. One installer script per OS takes a
completely bare machine — no Python, no Node.js, nothing pre-installed — all
the way to a fully running background service, downloading everything it needs
itself.

---

## 📋 Table of Contents

1. [How It Works](#how-it-works)
2. [Every Script, and What It's For](#every-script-and-what-its-for)
3. [Quick Start](#quick-start)
4. [Get Google API Credentials](#get-google-api-credentials)
5. [Configuration](#configuration)
6. [Managing the Service](#managing-the-service)
7. [Troubleshooting](#troubleshooting)
8. [Uninstalling](#uninstalling)

---

## How It Works

```
Every N seconds (configurable):
  ┌─────────────────────────────────────────────────────────┐
  │  1. Script asks Google Drive API: "what's in scope?"     │
  │  2. Compares result with downloaded_files.json           │
  │  3. For each NEW file found:                             │
  │       a. Download it to your destination folder          │
  │          (same folder path as in Drive)                  │
  │       b. Mark it as downloaded in downloaded_files.json  │
  │       c. Delete it from Google Drive                     │
  │  4. Sleep → repeat                                        │
  └─────────────────────────────────────────────────────────┘
```

"Scope" is whatever you chose during setup: a single Drive folder (with all its
subfolders), or your entire Drive.

**Authentication** works via OAuth2 — you log in with your Google account once
in a browser, and the script saves a `token.json` file. After that, it
authenticates silently forever.

---

## Every Script, and What It's For

```
drive-auto-fetcher/
│
├── installer.ps1                Windows one-click installer. Installs Python
│                                 and Node.js if missing (winget, else a direct
│                                 download into .runtime/), installs PM2 and the
│                                 Python deps, runs the config wizard, logs in
│                                 to Google, and starts the PM2 service.
│
├── installer.sh                 Linux/macOS equivalent of installer.ps1. Uses
│                                 the system package manager (apt/dnf/yum/
│                                 pacman/zypper/apk, or Homebrew on macOS) if
│                                 available, otherwise downloads self-contained
│                                 Python/Node.js builds into .runtime/ — no
│                                 sudo, no system-wide changes either way.
│
├── src/
│   ├── drive_fetcher.py         All runtime logic: auth, folder scanning,
│   │                            downloading, deleting, tracking. This is what
│   │                            actually runs, on every OS, once set up.
│   └── configure.py             Interactive wizard — asks what to fetch and
│                                 where to save it, writes config.json.
│                                 Also runnable standalone: `python src/configure.py`
│
├── scripts/
│   ├── start-service.ps1 / .sh  (Re)starts the PM2-managed background service
│   │                            and registers it to auto-start on boot. Use
│   │                            this after installer already ran once, e.g.
│   │                            on a second machine or after a manual pm2 stop.
│   ├── stop-service.ps1 / .sh   Stops and removes the service from PM2.
│   ├── run-once.ps1 / .sh       Runs a single check-and-download pass in the
│   │                            foreground, then exits. Useful for testing
│   │                            config.json changes before trusting PM2 with them.
│   ├── run-watch.ps1 / .sh      Runs continuously in the foreground (blocks the
│   │                            terminal, Ctrl+C / close window to stop). Useful
│   │                            for watching live output without PM2 involved.
│   ├── windows-task-scheduler-alternative.ps1
│   │                            Alternative to PM2 on Windows: registers a
│   │                            Task Scheduler job instead. Use only if you'd
│   │                            rather not install Node.js/PM2 at all.
│   └── linux-systemd-alternative.sh
│                                 Alternative to PM2 on Linux: registers a
│                                 systemd --user service instead. Same idea —
│                                 only needs Python, no Node.js/PM2.
│
├── ecosystem.config.js          PM2 process definition (name, restart policy,
│                                 log files, and which Python interpreter to use).
├── requirements.txt             Python dependencies (Google API client libraries).
├── config.example.json          Template/reference only — the program never
│                                 reads this file, only config.json.
│
├── config.json                  YOU create this (via the wizard) — your settings.
├── credentials.json              YOU create this — your Google OAuth2 app credentials.
├── token.json                    AUTO-CREATED after first login — your Google session.
├── downloaded_files.json         AUTO-CREATED at runtime — dedup tracking.
├── drive_fetcher.log             AUTO-CREATED at runtime — full action log.
├── pm2_out.log / pm2_err.log     AUTO-CREATED by PM2 — stdout / stderr.
└── .runtime/                     AUTO-CREATED by the installers if Python/Node.js
                                  had to be downloaded directly (no admin/sudo
                                  needed) instead of found on the system.
```

`config.json`, `credentials.json`, `token.json`, `.runtime/`, and all the
auto-created files are gitignored — they're machine-specific and never
committed.

---

## Quick Start

You need three things, none of which you have to install by hand:

| Tool | Purpose |
|------|---------|
| **Python 3.10+** | Runs the script |
| **Node.js** | Required by PM2 |
| **PM2** | Process manager |

### Step 1 — Get Google API credentials

Before running the installer, you need a `credentials.json` file from Google.
See [Get Google API Credentials](#get-google-api-credentials) below — a
one-time, five-minute step that can't be automated (it's your own Google Cloud
project).

### Step 2 — Run the installer for your OS

**Windows** — double-click **`installer.ps1`** (or, if that just opens it in an
editor: right-click → **Run with PowerShell**, or run from a terminal:
`powershell -ExecutionPolicy Bypass -File installer.ps1`).

**Linux / macOS** — from a terminal:
```bash
chmod +x installer.sh
./installer.sh
```

Either way, on a completely bare machine, the installer will:

1. Detect that Python is missing and install it automatically
   (Windows: `winget`, falling back to a direct download from python.org;
   Linux/macOS: the system package manager, falling back to a self-contained
   build downloaded into `.runtime/` — no admin/sudo needed for the fallback)
2. Do the same for Node.js
3. Create an isolated Python environment and install dependencies from
   `requirements.txt`
4. Install PM2
5. Ask you (interactively) what to fetch and where to save it, and write
   `config.json`
6. Open your browser for the one-time Google login and save `token.json`
7. Start the service under PM2 and register it to auto-start on boot

It's safe to re-run — every step is skipped if it's already done. If Python or
Node.js were just installed via `winget`, you may need to close the terminal
and re-run the script once so the new PATH is picked up (the script will tell
you if this happens).

> **Headless Linux server?** The Google login step opens a browser, which a
> headless machine doesn't have. Run the installer up through the login step on
> a desktop machine instead, then copy the resulting `token.json` (and
> `config.json`) over to the server.

---

## Get Google API Credentials

This gives the script permission to access your Google Drive.

1. Go to: **https://console.cloud.google.com/**

2. Click **"Select a project"** at the top → **"New Project"**
   - Name it anything (e.g. `DriveAutoFetcher`) → **Create**

3. In the left sidebar: **APIs & Services → Library**
   - Search: `Google Drive API` → click it → **Enable**

4. Left sidebar: **APIs & Services → OAuth consent screen**
   - User type: **External** → **Create**
   - App name: `DriveAutoFetcher` (anything)
   - User support email: your Gmail
   - Scroll down → **Save and Continue** through all steps
   - On the **"Test users"** page → **+ Add Users**
   - Add your Gmail address
   - **Save and Continue**

5. Left sidebar: **APIs & Services → Credentials**
   - **+ Create Credentials** → **OAuth client ID**
   - Application type: **Desktop app**
   - Name: anything → **Create**
   - Click **⬇ Download JSON**

6. Rename the downloaded file to exactly: **`credentials.json`**

7. Place `credentials.json` in the **repo root** (same place as `README.md`)

---

## Configuration

All behavior is controlled by `config.json` at the repo root:

```json
{
  "mode": "folder",
  "folder_id": "1iPZHhDGWwe3outDkz467pkgTkSCYN2Kw",
  "destination_path": "D:/Youtube",
  "delete_after_download": true,
  "check_interval_seconds": 60
}
```

| Field | Values | Meaning |
|-------|--------|---------|
| `mode` | `"folder"` or `"drive"` | Fetch one specific Drive folder, or your entire Drive |
| `folder_id` | Drive folder ID | Required when `mode` is `"folder"`; ignored otherwise |
| `destination_path` | Any local path | Where files are saved, e.g. `D:/Youtube` or `/home/you/GoogleDrive` |
| `delete_after_download` | `true` / `false` | Delete each file from Drive right after downloading it |
| `check_interval_seconds` | Number | How often watch mode checks Drive for new files |

The easiest way to create or update this file is the interactive wizard
(also runnable standalone, any time):

```bash
python src/configure.py      # Windows: use the same "python" the installer used
```

It asks you to choose folder-vs-whole-drive, paste a folder URL or ID (it
extracts the ID automatically), pick a destination, and set the rest.

**Finding a folder ID manually:** open the folder in Google Drive — the URL looks like:
```
https://drive.google.com/drive/folders/1iPZHhDGWwe3outDkz467pkgTkSCYN2Kw
                                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                        Copy only THIS part — no ?usp=... at the end
```

After changing `config.json`, restart the service:
```bash
pm2 restart drive-auto-fetcher
```

---

## Managing the Service

Once running, control it using PM2 commands in any terminal:

```bash
pm2 list                             # see all processes and their status
pm2 logs drive-auto-fetcher          # watch live logs (Ctrl+C to exit)
pm2 logs drive-auto-fetcher --lines 100
pm2 restart drive-auto-fetcher       # after changing config.json
pm2 stop drive-auto-fetcher          # stop temporarily
pm2 start drive-auto-fetcher         # start it again
pm2 delete drive-auto-fetcher        # remove it from PM2 entirely
```

| Icon | Meaning |
|------|---------|
| 🟢 online | Running normally |
| 🔴 stopped | Manually stopped |
| 🟠 errored | Crashed (check logs) |

`scripts/start-service.{ps1,sh}` and `scripts/stop-service.{ps1,sh}` wrap the
common start/stop sequence (including the PM2 auto-start-on-boot registration),
for when you want that without re-running the whole installer.

### Not using PM2

If you'd rather avoid installing Node.js/PM2 altogether:
- **Windows**: `scripts/windows-task-scheduler-alternative.ps1` registers a
  Task Scheduler job that runs in watch mode on login instead. Run it once,
  from an elevated PowerShell.
- **Linux**: `scripts/linux-systemd-alternative.sh` registers a
  `systemd --user` service instead. Run it once (no sudo needed, though it
  will suggest one `loginctl` command to let the service run after logout).

---

## Troubleshooting

### "No files found" / "ZERO items returned by API"

Run `pm2 logs drive-auto-fetcher` and look for the DEBUG section.
It lists everything the API can see. Common causes:

| Cause | Fix |
|-------|-----|
| `folder_id` has `?usp=drive_link` at the end | Remove everything after the ID in `config.json` |
| Files owned by a different Google account | Log in with the account that owns the folder |
| Gmail not added as Test User | Google Cloud → OAuth consent screen → Test users → add your Gmail |
| Token is for the wrong account | Delete `token.json`, run `python src/drive_fetcher.py --auth-only` |

### "Access blocked: has not completed Google verification"

Your Gmail isn't added as a Test User.
1. Go to https://console.cloud.google.com/
2. **APIs & Services → OAuth consent screen → Test users**
3. Add your Gmail → Save
4. Delete `token.json` and run `python src/drive_fetcher.py --auth-only` again

### Script keeps restarting / crashing

```bash
pm2 logs drive-auto-fetcher --lines 50
```
Look at the error lines. Common cause: `token.json` expired.
Fix: delete `token.json`, run `python src/drive_fetcher.py --auth-only`, then
`pm2 restart drive-auto-fetcher`.

### Files downloading again after restart

Do **not** delete `downloaded_files.json`. That file is the memory of what's
already been downloaded. If it's deleted, the script has no way to know what
was already fetched (but since files are also deleted from Drive, it won't
actually re-download anything — it just won't find them in Drive either).

### PM2 not starting after reboot

Run the installer again, or manually:
```bash
pm2 save
pm2 startup      # follow the printed instructions (Linux/macOS)
pm2-startup install   # Windows
```

### Installer says Python/Node "isn't visible in this terminal yet" (Windows)

`winget` updated your system PATH, but the *current* terminal window was
opened before that happened. Close the window, open a new one, and re-run
`installer.ps1`.

### `pip install` fails with "externally-managed-environment" (Linux)

This is expected on modern Debian/Ubuntu — `installer.sh` avoids it entirely
by installing dependencies into `.runtime/venv` rather than the system Python.
If you're invoking `python3 src/drive_fetcher.py` directly instead of through
that venv, use `.runtime/venv/bin/python3` instead of the system `python3`.

---

## Uninstalling

**To stop the service temporarily:**
```bash
pm2 stop drive-auto-fetcher
```

**To remove it completely:**

Run `scripts/stop-service.{ps1,sh}`, then:
```bash
pm2-startup uninstall   # Windows
pm2 unstartup            # Linux/macOS
```

This removes the boot-time auto-start entry. PM2 itself stays installed but
won't start anything on boot.

If you used the Task Scheduler / systemd alternative instead of PM2:
```powershell
# Windows
Unregister-ScheduledTask -TaskName 'DriveAutoFetcher' -Confirm:$false
```
```bash
# Linux
systemctl --user disable --now drive-auto-fetcher
```
