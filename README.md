# 📁 Drive Auto-Fetcher

A background service that watches your Google Drive folder, downloads every file
to `D:\Youtube` with the **exact same folder structure**, and **deletes each file
from Drive** the moment it finishes downloading. New files are detected every
60 seconds. Already-downloaded files are never re-downloaded.

Managed by **PM2** — a professional process manager that keeps the script running
24/7 and automatically restarts it on crashes or Windows reboots.

---

## 📋 Table of Contents

1. [How It Works](#how-it-works)
2. [What's in This Folder](#whats-in-this-folder)
3. [Prerequisites](#prerequisites)
4. [Setup Guide](#setup-guide)
5. [Using PM2](#using-pm2)
6. [File Structure on Your PC](#file-structure-on-your-pc)
7. [Configuration](#configuration)
8. [Troubleshooting](#troubleshooting)
9. [How to Uninstall](#how-to-uninstall)

---

## How It Works

```
Every 60 seconds:
  ┌─────────────────────────────────────────────────────────┐
  │  1. Script asks Google Drive API: "what's in the folder?"│
  │  2. Compares result with downloaded_files.json           │
  │  3. For each NEW file found:                             │
  │       a. Download it to D:\Youtube (same folder path)   │
  │       b. Mark it as downloaded in downloaded_files.json  │
  │       c. Delete it from Google Drive                     │
  │  4. Sleep 60 seconds → repeat                            │
  └─────────────────────────────────────────────────────────┘
```

**PM2** sits on top of this and:
- Keeps the script running in the background (no window open)
- Restarts it automatically if it crashes
- Starts it automatically when Windows boots
- Collects all logs in one place

**Authentication** works via OAuth2 — you log in with your Google account
once in a browser, and the script saves a `token.json` file. After that,
the script authenticates silently forever (PM2 never needs a browser).

---

## What's in This Folder

```
drive-auto-fetcher/
│
├── drive_fetcher.py          ← The main Python script
│                               All the logic lives here:
│                               authentication, folder scanning,
│                               downloading, deleting, tracking
│
├── ecosystem.config.js       ← PM2 configuration
│                               Tells PM2: which script to run,
│                               what arguments, log file names,
│                               restart policy, etc.
│
├── requirements.txt          ← Python library dependencies
│                               (Google API client libraries)
│
├── 1_first_time_setup.bat    ← Run ONCE before anything else
│                               Installs Python deps + opens
│                               browser for Google login
│
├── 2_start_pm2.bat           ← Start the background service
│                               Installs PM2 if needed,
│                               registers Windows auto-start
│
├── 3_stop_pm2.bat            ← Stop the background service
│
├── credentials.json          ← YOU create this (Step 3 below)
│                               Google OAuth2 app credentials
│                               downloaded from Google Cloud
│
├── token.json                ← AUTO-CREATED after first login
│                               Your Google session token
│                               DO NOT delete this or share it
│
├── downloaded_files.json     ← AUTO-CREATED at runtime
│                               List of Drive file IDs already
│                               downloaded. Prevents re-downloads
│
├── drive_fetcher.log         ← AUTO-CREATED at runtime
│                               Full log of every action taken
│
├── pm2_out.log               ← AUTO-CREATED by PM2
│                               stdout from the script
│
└── pm2_err.log               ← AUTO-CREATED by PM2
                                stderr / crash output
```

---

## Prerequisites

You need three things installed before setup:

| Tool | Purpose | Download |
|------|---------|----------|
| **Python 3.10+** | Runs the script | https://www.python.org/downloads/ |
| **Node.js 18+** | Required by PM2 | https://nodejs.org/ |
| **PM2** | Process manager | Installed automatically by `2_start_pm2.bat` |

> ⚠️ When installing Python, check **"Add Python to PATH"**.
> When installing Node.js, it adds itself to PATH automatically.

---

## Setup Guide

Follow these steps **in order**. Do each one only once.

---

### Step 1 — Install Python and Node.js

- Python: https://www.python.org/downloads/ → ✅ check "Add Python to PATH"
- Node.js: https://nodejs.org/ → download the LTS version

Verify in a terminal (`Win + R` → type `cmd` → Enter):
```
python --version
node --version
```
Both should print a version number.

---

### Step 2 — Create `D:\Youtube` folder

Make sure the folder exists where files will be saved:
```
D:\Youtube\
```
Create it manually in File Explorer if it doesn't exist.

---

### Step 3 — Get Google API Credentials

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
   - Add your Gmail address (e.g. `quantumlogicslimited@gmail.com`)
   - **Save and Continue**

5. Left sidebar: **APIs & Services → Credentials**
   - **+ Create Credentials** → **OAuth client ID**
   - Application type: **Desktop app**
   - Name: anything → **Create**
   - Click **⬇ Download JSON**

6. Rename the downloaded file to exactly: **`credentials.json`**

7. Place `credentials.json` in **this folder** (same place as `drive_fetcher.py`)

---

### Step 4 — First Time Setup (One-Time Google Login)

Double-click: **`1_first_time_setup.bat`**

This will:
- Install Python dependencies (`google-api-python-client` etc.)
- Open your browser for Google login
- You log in → click **Allow**
- Script saves `token.json` and exits

> ✅ After this step, `token.json` exists in the folder.
> PM2 will use this silently — the browser never opens again.

---

### Step 5 — Start with PM2

Double-click: **`2_start_pm2.bat`**

This will:
- Install PM2 globally via npm (if not already installed)
- Install `pm2-windows-startup` for auto-boot support
- Start the script as a background process
- Save the PM2 process list
- Register PM2 to start automatically when Windows boots

> ✅ After this, the fetcher runs in the background forever —
> even after you close all windows, even after reboots.

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

# Restart the service (e.g. after changing drive_fetcher.py)
pm2 restart drive-auto-fetcher

# Stop the service temporarily
pm2 stop drive-auto-fetcher

# Start it again after stopping
pm2 start drive-auto-fetcher

# Remove it from PM2 entirely
pm2 delete drive-auto-fetcher
```

**PM2 status icons:**
| Icon | Meaning |
|------|---------|
| 🟢 online | Running normally |
| 🔴 stopped | Manually stopped |
| 🟠 errored | Crashed (check logs) |

---

## File Structure on Your PC

The script mirrors the **exact same folder structure** from Drive to your PC.

**If your Google Drive folder looks like:**
```
📁 Google Drive Folder/
├── 📄 intro.mp4
├── 📄 tutorial.mp4
└── 📁 Lectures/
    ├── 📄 lecture_01.mp4
    └── 📄 lecture_02.mp4
```

**Your `D:\Youtube` will look like:**
```
D:\Youtube\
├── intro.mp4
├── tutorial.mp4
└── Lectures\
    ├── lecture_01.mp4
    └── lecture_02.mp4
```

After downloading, each file is deleted from Drive. Once a subfolder is
emptied, the subfolder itself is also deleted from Drive.

---

## Configuration

Open `drive_fetcher.py` and edit the **CONFIG** block at the top:

```python
FOLDER_ID             = "1iPZHhDGWwe3outDkz467pkgTkSCYN2Kw"  # Drive folder ID
SAVE_DIR              = "D:/Youtube"                           # Save location on PC
DELETE_AFTER_DOWNLOAD = True    # Set False to keep files in Drive
CHECK_INTERVAL        = 60      # Seconds between checks (in watch mode)
```

**Finding your Folder ID:**
Open the folder in Google Drive. The URL looks like:
```
https://drive.google.com/drive/folders/1iPZHhDGWwe3outDkz467pkgTkSCYN2Kw
                                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                        Copy only THIS part — no ?usp=... at the end
```

After changing the config, restart the service:
```bash
pm2 restart drive-auto-fetcher
```

---

## Troubleshooting

### "No files found in the folder"

Run `pm2 logs drive-auto-fetcher` and look for the DEBUG section.
It lists everything the API can see. Common causes:

| Cause | Fix |
|-------|-----|
| FOLDER_ID has `?usp=drive_link` at the end | Remove everything after the ID |
| Files owned by a different Google account | Log in with the account that owns the folder |
| Gmail not added as Test User | Go to Google Cloud → OAuth consent screen → Test users → add your Gmail |
| Token is for wrong account | Delete `token.json`, run `1_first_time_setup.bat` again |

### "Access blocked: has not completed Google verification"

Your Gmail isn't added as a Test User.
1. Go to https://console.cloud.google.com/
2. **APIs & Services → OAuth consent screen → Test users**
3. Add your Gmail → Save
4. Delete `token.json` and run `1_first_time_setup.bat` again

### Script keeps restarting / crashing

```bash
pm2 logs drive-auto-fetcher --lines 50
```
Look at the error lines. Common cause: `token.json` expired.
Fix: delete `token.json`, run `1_first_time_setup.bat`, then `pm2 restart drive-auto-fetcher`.

### Files downloading again after restart

Do **not** delete `downloaded_files.json`. That file is the memory of what's
already been downloaded. If it's deleted, the script has no way to know what
was already fetched (but since files are also deleted from Drive, it won't
actually re-download anything — it just won't find them in Drive either).

### PM2 not starting after reboot

Run `2_start_pm2.bat` again. Then:
```bash
pm2 save
pm2-startup install
```

---

## How to Uninstall

**To stop the service temporarily:**
```bash
pm2 stop drive-auto-fetcher
```

**To remove it completely:**

Double-click `3_stop_pm2.bat`, then run:
```bash
pm2-startup uninstall
```

This removes the Windows auto-start entry. PM2 itself stays installed
but won't start anything on boot.
