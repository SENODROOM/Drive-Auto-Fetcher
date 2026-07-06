# 📁 Drive Auto-Fetcher

A background service that watches a Google Drive folder — or your entire Drive —
downloads every file to a folder on your PC with the **exact same folder structure**,
and **deletes each file from Drive** the moment it finishes downloading. New files
are detected on a configurable interval. Already-downloaded files are never
re-downloaded.

Managed by **PM2** — a professional process manager that keeps the script running
24/7 and automatically restarts it on crashes or Windows reboots.

One script (`scripts/setup.bat`) takes a completely bare Windows machine —
no Python, no Node.js, nothing pre-installed — all the way to a fully running
background service.

---

## 📋 Table of Contents

1. [How It Works](#how-it-works)
2. [Project Layout](#project-layout)
3. [Quick Start](#quick-start)
4. [Get Google API Credentials](#get-google-api-credentials)
5. [Configuration](#configuration)
6. [Using PM2](#using-pm2)
7. [Alternative: Task Scheduler](#alternative-task-scheduler)
8. [Troubleshooting](#troubleshooting)
9. [Uninstalling](#uninstalling)

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

**PM2** sits on top of this and:
- Keeps the script running in the background (no window open)
- Restarts it automatically if it crashes
- Starts it automatically when Windows boots
- Collects all logs in one place

**Authentication** works via OAuth2 — you log in with your Google account
once in a browser, and the script saves a `token.json` file. After that,
the script authenticates silently forever (PM2 never needs a browser).

---

## Project Layout

```
drive-auto-fetcher/
│
├── src/
│   ├── drive_fetcher.py       All the runtime logic: authentication, folder
│   │                          scanning, downloading, deleting, tracking
│   └── configure.py           Interactive wizard that writes config.json
│
├── scripts/
│   ├── setup.bat / setup.ps1  Run ONCE — installs everything and starts the service
│   ├── run_once.bat           Manually run a single check-and-download pass
│   ├── run_watch.bat          Manually run continuously in a foreground window
│   ├── pm2_start.bat          (Re)start the PM2-managed background service
│   ├── pm2_stop.bat           Stop and remove the PM2-managed service
│   └── install_task_scheduler.ps1
│                              Alternative to PM2, using Windows Task Scheduler
│
├── ecosystem.config.js        PM2 configuration (process name, restart policy, logs)
├── requirements.txt           Python dependencies (Google API client libraries)
├── config.example.json        Template — copy/wizard-generate this into config.json
│
├── config.json                 YOU create this (via the setup wizard) — your settings
├── credentials.json            YOU create this — Google OAuth2 app credentials
├── token.json                  AUTO-CREATED after first login — your Google session
├── downloaded_files.json       AUTO-CREATED at runtime — dedup tracking
├── drive_fetcher.log           AUTO-CREATED at runtime — full action log
├── pm2_out.log / pm2_err.log   AUTO-CREATED by PM2 — stdout / stderr
```

`config.json`, `credentials.json`, `token.json`, and all the auto-created files
are gitignored — they're machine-specific and never committed.

---

## Quick Start

You need three things, none of which you have to install by hand:

| Tool | Purpose |
|------|---------|
| **Python 3.10+** | Runs the script |
| **Node.js LTS** | Required by PM2 |
| **PM2** | Process manager |

### Step 1 — Get Google API credentials

Before running setup, you need a `credentials.json` file from Google. See
[Get Google API Credentials](#get-google-api-credentials) below — this is a
one-time, five-minute step that can't be automated (it's your own Google Cloud
project).

### Step 2 — Run the setup script

Double-click **`scripts/setup.bat`**.

On a completely bare machine, this single script will:

1. Detect that Python is missing and install it automatically (via `winget`)
2. Detect that Node.js is missing and install it automatically (via `winget`)
3. Install the Python dependencies (`pip install -r requirements.txt`)
4. Install PM2 and `pm2-windows-startup` (via `npm`)
5. Ask you (interactively) what to fetch and where to save it, and write `config.json`
6. Open your browser for the one-time Google login and save `token.json`
7. Start the service under PM2 and register it to auto-start on Windows boot

It's safe to re-run — every step is skipped if it's already done. If Python or
Node.js were just installed, you may need to close the window and re-run the
script once so the new PATH is picked up.

> **No admin rights / no winget?** `winget` ships with modern Windows 10/11.
> If it's unavailable, the script will tell you exactly what to install
> manually and where from — re-run it afterward to continue.

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
| `destination_path` | Any local path | Where files are saved, e.g. `D:/Youtube` |
| `delete_after_download` | `true` / `false` | Delete each file from Drive right after downloading it |
| `check_interval_seconds` | Number | How often watch mode checks Drive for new files |

The easiest way to create or update this file is the interactive wizard:

```bash
python src/configure.py
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

## Using PM2

Once running, you control the service using PM2 commands in any terminal:

```bash
# See all running PM2 processes and their status
pm2 list

# Watch live logs (Ctrl+C to exit)
pm2 logs drive-auto-fetcher

# See last 100 log lines
pm2 logs drive-auto-fetcher --lines 100

# Restart the service (e.g. after changing config.json)
pm2 restart drive-auto-fetcher

# Stop the service temporarily
pm2 stop drive-auto-fetcher

# Start it again after stopping
pm2 start drive-auto-fetcher

# Remove it from PM2 entirely
pm2 delete drive-auto-fetcher
```

| Icon | Meaning |
|------|---------|
| 🟢 online | Running normally |
| 🔴 stopped | Manually stopped |
| 🟠 errored | Crashed (check logs) |

`scripts/pm2_start.bat` and `scripts/pm2_stop.bat` wrap the common start/stop
sequence, including the PM2/`pm2-windows-startup` install check.

---

## Alternative: Task Scheduler

If PM2/Node.js isn't an option on a given machine, `scripts/install_task_scheduler.ps1`
registers the fetcher as a Windows Task Scheduler job that runs in watch mode on
every login instead (no crash auto-restart beyond Task Scheduler's own retry
policy). Run it once, as Administrator, from an elevated PowerShell:

```powershell
scripts\install_task_scheduler.ps1
```

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

Run `scripts\setup.bat` again, or manually:
```bash
pm2 save
pm2-startup install
```

### `setup.ps1` says Python/Node "isn't visible in this terminal yet"

The installer updated your system PATH, but the *current* terminal window
was opened before that happened. Close the window, open a new one, and
re-run `scripts\setup.bat`.

---

## Uninstalling

**To stop the service temporarily:**
```bash
pm2 stop drive-auto-fetcher
```

**To remove it completely:**

Run `scripts\pm2_stop.bat`, then:
```bash
pm2-startup uninstall
```

This removes the Windows auto-start entry. PM2 itself stays installed
but won't start anything on boot.

If you used the Task Scheduler alternative instead of PM2:
```powershell
Unregister-ScheduledTask -TaskName 'DriveAutoFetcher' -Confirm:$false
```
