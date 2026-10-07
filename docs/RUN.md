# Running Drive Auto-Fetcher

A step-by-step guide that takes you from a fresh copy of this repo to a service
running in the background. Run every command from the repo root (the folder
that contains `README.md`).

> **Read this first.** With `delete_after_download` set to `true` (the default),
> files are **permanently deleted** from Google Drive once they have downloaded.
> They do not go to the Drive trash. Read
> [What it deletes and what it skips](#what-it-deletes-and-what-it-skips)
> before pointing this at a folder you care about.

## Contents

1. [Create Google credentials](#step-1--create-google-credentials)
2. [Install the tools](#step-2--install-the-tools)
3. [Choose what to fetch](#step-3--choose-what-to-fetch)
4. [Log in to Google](#step-4--log-in-to-google)
5. [Do a test run](#step-5--do-a-test-run)
6. [Run it continuously](#step-6--run-it-continuously)
7. [Check on it, change it, stop it](#step-7--check-on-it-change-it-stop-it)

**Shortcut:** once you have `credentials.json` from Step 1, the installer does
Steps 2 to 6 in one go:

```powershell
powershell -ExecutionPolicy Bypass -File installer.ps1
```

It skips anything already done, so it is safe to re-run. It also starts the
background service straight away with no test run, so follow the steps below
instead if you want to check your settings first.

### On Linux or macOS

The commands in this guide are written for Windows PowerShell. Swap them like this:

| Windows | Linux / macOS |
|---------|---------------|
| `python` | `python3`, or `.runtime/venv/bin/python3` if `installer.sh` created it |
| `powershell -ExecutionPolicy Bypass -File scripts\NAME.ps1` | `./scripts/NAME.sh` (run `chmod +x scripts/*.sh` once) |
| `powershell -ExecutionPolicy Bypass -File installer.ps1` | `./installer.sh` |

---

## Step 1 — Create Google credentials

This is the one step nothing can automate, because the credentials belong to
your own Google Cloud project. It takes about five minutes.

1. Open <https://console.cloud.google.com/> and sign in with the Google account
   that owns the Drive files.
2. Click **Select a project** → **New Project**, give it any name, and click **Create**.
3. Go to **APIs & Services → Library**, search for `Google Drive API`, open it,
   and click **Enable**.
4. Go to **APIs & Services → OAuth consent screen**. (Newer versions of the
   console call this **Google Auth Platform**, with **Branding**, **Audience**
   and **Clients** pages.)
   - User type: **External**
   - App name: anything, for example `DriveAutoFetcher`
   - Support email: your own address
   - Under **Test users**, add the Gmail address you will log in with
5. Go to **APIs & Services → Credentials** → **Create Credentials** →
   **OAuth client ID**.
   - Application type: **Desktop app**
   - Click **Create**, then **Download JSON**
6. Rename the downloaded file to exactly `credentials.json` and move it into
   the repo root.

**Check:** `credentials.json` sits next to `README.md`.

## Step 2 — Install the tools

| Tool | Needed for | Check it is installed |
|------|------------|-----------------------|
| Python 3.10 or newer | Everything | `python --version` |
| Node.js and PM2 | The background service only | `node --version` and `pm2 --version` |

Install the Python packages:

```powershell
python -m pip install -r requirements.txt
```

If you want the background service, install PM2 as well:

```powershell
npm install -g pm2 pm2-windows-startup
```

If Python or Node.js is missing, run the installer from the shortcut above. It
installs both for you.

**Check:** `python -c "import googleapiclient"` prints nothing and no error.

## Step 3 — Choose what to fetch

Run the setup wizard:

```powershell
python src\configure.py
```

It asks four things and writes `config.json`:

1. **What to fetch:** one Drive folder (with all its subfolders) or your whole Drive.
2. **Which folder:** paste the folder's URL from your browser. The wizard pulls
   the ID out of it.
3. **Where to save:** a local folder, for example `D:/Youtube`. It is created
   if it does not exist.
4. **Delete after download** and **check interval** in seconds (minimum 10).

If `config.json` already exists, the wizard shows it and asks before
overwriting. The result looks like this:

```json
{
  "mode": "folder",
  "folder_id": "1iPZHhDGWwe3outDkz467pkgTkSCYN2Kw",
  "destination_path": "D:/Youtube",
  "delete_after_download": true,
  "check_interval_seconds": 60
}
```

If you edit the file by hand, `folder_id` must be the ID alone. A value copied
from a share link often ends in `?usp=drive_link`; remove that part, or the
script will find nothing.

**Tip:** set `"delete_after_download": false` for your first run, and switch
it to `true` once you have seen the files arrive.

## Step 4 — Log in to Google

```powershell
python src\drive_fetcher.py --auth-only
```

Your browser opens. Then:

1. Pick the Google account you added as a test user in Step 1.
2. On the "Google hasn't verified this app" screen, click **Advanced**, then
   **Go to (your app name)**.
3. Click **Allow**.

The script saves `token.json` and exits without downloading anything. You only
do this once; later runs log in silently.

**Check:** `token.json` now exists in the repo root.

## Step 5 — Do a test run

This makes one pass over Drive, downloads whatever is new, and exits:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run-once.ps1
```

Look for these lines in the output:

- `Total items found: N` means the script can see your files. If it says
  `ZERO items returned by API`, see [Troubleshooting](#troubleshooting).
- `Saved: <path>` appears once for each downloaded file.
- `Done.` appears at the end.

**Check:** the files are in your destination folder, with the same subfolder
layout they had in Drive.

## Step 6 — Run it continuously

Pick one of the two.

**In a terminal window.** It checks Drive on the interval from `config.json`
and stops when you press Ctrl+C or close the window:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run-watch.ps1
```

**As a background service.** PM2 keeps it running, restarts it if it crashes,
and starts it again after a reboot:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start-service.ps1
```

**Check:** `pm2 list` shows `drive-auto-fetcher` with the status `online`.

To run in the background without Node.js or PM2, see "Not using PM2" in the
[README](../README.md#not-using-pm2).

## Step 7 — Check on it, change it, stop it

| To do this | Run this |
|------------|----------|
| See whether it is running | `pm2 list` |
| Watch live output (Ctrl+C to leave) | `pm2 logs drive-auto-fetcher` |
| Apply a change to `config.json` | `pm2 restart drive-auto-fetcher` |
| Pause it | `pm2 stop drive-auto-fetcher` |
| Resume it | `pm2 start drive-auto-fetcher` |
| Stop it and remove it from PM2 | `powershell -ExecutionPolicy Bypass -File scripts\stop-service.ps1` |
| Remove the start-after-reboot entry | `pm2-startup uninstall` |

The full history of every download and deletion is in `drive_fetcher.log` in
the repo root, whichever way you run it.

---

## What it deletes and what it skips

These apply when `delete_after_download` is `true`:

- **Deletion is permanent.** Files are removed outright and cannot be restored
  from the Drive trash.
- **Each file is deleted right after it is saved locally.**
- **Each subfolder is deleted once the script has gone through it, along with
  anything of yours still inside it.** That includes files whose download
  failed and any Google Docs, Sheets or Slides, which the script never
  downloads. Keep those out of the subfolders, or leave deletion off.
- **The top-level folder you configured is never deleted.** Google Docs, Sheets
  and Slides sitting directly in it are skipped and left alone.

These apply always:

- **Google Docs, Sheets and Slides are not downloaded.** Only regular files are
  (videos, images, PDFs, archives and so on).
- **Each file is held in memory while it downloads.** The machine needs more
  free RAM than the size of your largest file.
- **`downloaded_files.json` is the record of what has already been fetched.**
  If you delete it while deletion is off, everything downloads again.

## Troubleshooting

| What you see | Cause | Fix |
|--------------|-------|-----|
| `credentials.json not found` | Step 1 was skipped, or the file has a different name or location | Put `credentials.json` in the repo root |
| "Access blocked: has not completed Google verification" | Your account is not a test user | Add your Gmail under **Test users** (Step 1.4), delete `token.json`, repeat Step 4 |
| `ZERO items returned by API` | `folder_id` has `?usp=...` on the end, or you logged in with an account that does not own the folder | Fix `folder_id` in `config.json`, or delete `token.json` and repeat Step 4 with the right account |
| "running scripts is disabled on this system" | PowerShell execution policy | Use the full `powershell -ExecutionPolicy Bypass -File ...` form shown in this guide |
| `pm2` is not recognized | PM2 is not installed, or the terminal was opened before it was | Run `npm install -g pm2 pm2-windows-startup`, then open a new terminal |
| `Missing dependencies` | The Python packages are not installed for the Python being used | Run `python -m pip install -r requirements.txt` |
| It worked for about a week, then every check logs an error (often `invalid_grant`) | Google expires the login after 7 days while the OAuth app's publishing status is "Testing" | Delete `token.json`, repeat Step 4, run `pm2 restart drive-auto-fetcher`. To stop it recurring, set the publishing status to "In production" on the consent screen page; the "unverified app" warning at login stays, which is fine for personal use |
| `drive-auto-fetcher` shows `errored` in `pm2 list` | It crashed more than 10 times in a row | Run `pm2 logs drive-auto-fetcher --lines 50`, fix the error shown, then `pm2 restart drive-auto-fetcher` |

More cases are covered in the [README](../README.md#troubleshooting).
