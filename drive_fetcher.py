"""
Google Drive Auto-Fetcher v4
=============================
- Downloads ALL files from Google Drive folder (including subfolders)
- Mirrors exact folder structure to D:/Youtube
- Sanitizes filenames — removes characters Windows forbids (? * : " < > | / \)
- Deletes each file from Drive immediately after successful download
- Tracks downloaded files so duplicates are never re-downloaded
- Runs on every Windows login OR continuously in watch mode
"""

import os
import sys
import json
import io
import re
import logging
import time
from pathlib import Path

# ─── CONFIG ────────────────────────────────────────────────────────────────────
FOLDER_ID             = "1iPZHhDGWwe3outDkz467pkgTkSCYN2Kw"
SAVE_DIR              = "D:/Youtube"
CREDENTIALS_FILE      = "credentials.json"
TOKEN_FILE            = "token.json"
TRACKING_FILE         = "downloaded_files.json"
LOG_FILE              = "drive_fetcher.log"
DELETE_AFTER_DOWNLOAD = True
CHECK_INTERVAL        = 60
# ───────────────────────────────────────────────────────────────────────────────

SCOPES = ["https://www.googleapis.com/auth/drive"]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger(__name__)


# ── Windows Filename Sanitizer ─────────────────────────────────────────────────

# Characters Windows forbids in file/folder names
_WIN_FORBIDDEN = r'[<>:"/\\|?*]'
# Control characters ASCII 0-31
_WIN_CONTROL   = r'[\x00-\x1f]'
# Names Windows reserves (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
_WIN_RESERVED  = re.compile(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)', re.IGNORECASE
)

def sanitize_name(name: str) -> str:
    """
    Make a Google Drive file/folder name safe for Windows.

    Examples:
      "What is Dot Product? Simple Guide"  ->  "What is Dot Product_ Simple Guide"
      "Video: Part 1/2"                    ->  "Video_ Part 1_2"
      "Report <2024>"                      ->  "Report _2024_"
    """
    safe = re.sub(_WIN_FORBIDDEN, '_', name)   # replace forbidden chars
    safe = re.sub(_WIN_CONTROL, '', safe)       # remove control chars
    safe = safe.strip('. ')                     # strip leading/trailing dots/spaces
    if _WIN_RESERVED.match(safe):               # handle reserved names
        safe = safe + '_'
    if not safe:                                # fallback if name is now empty
        safe = '_unnamed_'
    return safe


# ── Tracking ───────────────────────────────────────────────────────────────────

def load_downloaded():
    if os.path.exists(TRACKING_FILE):
        try:
            with open(TRACKING_FILE, "r") as f:
                return set(json.load(f))
        except Exception:
            pass
    return set()


def save_downloaded(downloaded_ids):
    with open(TRACKING_FILE, "w") as f:
        json.dump(list(downloaded_ids), f, indent=2)


# ── Auth ───────────────────────────────────────────────────────────────────────

def get_drive_service():
    try:
        from google.oauth2.credentials import Credentials
        from google_auth_oauthlib.flow import InstalledAppFlow
        from google.auth.transport.requests import Request
        from googleapiclient.discovery import build
    except ImportError:
        log.error("Missing dependencies. Run:  pip install -r requirements.txt")
        sys.exit(1)

    creds = None

    if os.path.exists(TOKEN_FILE):
        creds = Credentials.from_authorized_user_file(TOKEN_FILE, SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                from google.auth.transport.requests import Request
                creds.refresh(Request())
                log.info("Token refreshed.")
            except Exception as e:
                log.warning(f"Token refresh failed ({e}), re-authenticating…")
                creds = None

        if not creds:
            if not os.path.exists(CREDENTIALS_FILE):
                log.error("credentials.json not found! See README.md Step 2.")
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file(CREDENTIALS_FILE, SCOPES)
            creds = flow.run_local_server(port=0, open_browser=True)
            log.info("Authentication successful.")

        with open(TOKEN_FILE, "w") as f:
            f.write(creds.to_json())

    return build("drive", "v3", credentials=creds)


# ── Drive Helpers ──────────────────────────────────────────────────────────────

def list_folder_contents(service, folder_id):
    """Return (files, subfolders) inside a Drive folder."""
    files = []
    folders = []
    page_token = None

    while True:
        resp = service.files().list(
            q=f"'{folder_id}' in parents and trashed = false",
            spaces="drive",
            fields="nextPageToken, files(id, name, mimeType, size)",
            pageToken=page_token,
        ).execute()

        for item in resp.get("files", []):
            if item["mimeType"] == "application/vnd.google-apps.folder":
                folders.append(item)
            else:
                files.append(item)

        page_token = resp.get("nextPageToken")
        if not page_token:
            break

    return files, folders


def debug_folder(service, folder_id):
    """Print everything in the folder — for troubleshooting."""
    log.info("=" * 60)
    log.info("DEBUG: Listing ALL items in Drive folder (including Google Docs)...")
    log.info(f"DEBUG: Folder ID = '{folder_id}'")
    page_token = None
    total = 0
    while True:
        resp = service.files().list(
            q=f"'{folder_id}' in parents and trashed = false",
            spaces="drive",
            fields="nextPageToken, files(id, name, mimeType, size)",
            pageToken=page_token,
        ).execute()
        items = resp.get("files", [])
        for item in items:
            size = item.get("size", "N/A")
            log.info(f"  FOUND: [{item['mimeType']}]  {item['name']}  (size={size})")
            total += 1
        page_token = resp.get("nextPageToken")
        if not page_token:
            break

    if total == 0:
        log.info("  ⚠  ZERO items returned by API.")
        log.info("  Possible reasons:")
        log.info("    1. The folder is actually empty")
        log.info("    2. Files are owned by a different Google account")
        log.info("    3. You don't have permission to view this folder")
        log.info("    4. The folder ID is wrong")
        log.info(f"  Try opening this URL to verify:")
        log.info(f"  https://drive.google.com/drive/folders/{folder_id}")
    else:
        log.info(f"  Total items found: {total}")
    log.info("=" * 60)


def download_file(service, file_id, file_name, dest_path):
    """Download a regular file from Drive."""
    from googleapiclient.http import MediaIoBaseDownload

    request = service.files().get_media(fileId=file_id)
    fh = io.BytesIO()
    downloader = MediaIoBaseDownload(fh, request, chunksize=8 * 1024 * 1024)

    done = False
    while not done:
        status, done = downloader.next_chunk()
        log.info(f"    ↓ {file_name}  [{int(status.progress() * 100)}%]")

    fh.seek(0)
    os.makedirs(os.path.dirname(dest_path) or ".", exist_ok=True)
    with open(dest_path, "wb") as f:
        f.write(fh.read())


def delete_item(service, item_id, name):
    """Permanently delete a file or folder from Drive."""
    try:
        service.files().delete(fileId=item_id).execute()
        log.info(f"    🗑  Deleted from Drive: {name}")
    except Exception as e:
        log.warning(f"    ⚠  Could not delete '{name}': {e}")


# ── Recursive Download ─────────────────────────────────────────────────────────

def process_folder(service, folder_id, folder_name, local_path, downloaded_ids):
    """
    Recursively download all files in a Drive folder to local_path.
    Mirrors the exact folder structure.
    Deletes each file from Drive immediately after download.
    """
    log.info(f"📂 Folder: {folder_name}  →  {local_path}")
    os.makedirs(local_path, exist_ok=True)

    files, subfolders = list_folder_contents(service, folder_id)
    log.info(f"   Found {len(files)} file(s) and {len(subfolders)} subfolder(s)")

    for f in files:
        fid   = f["id"]
        fname = f["name"]
        mime  = f["mimeType"]

        # Skip Google Workspace files (Docs, Sheets, Slides — can't download directly)
        if mime.startswith("application/vnd.google-apps."):
            log.warning(f"  ⏭  Skipping Google Workspace file (cannot download): {fname} [{mime}]")
            continue

        if fid in downloaded_ids:
            log.info(f"  ⏭  Already downloaded, skipping: {fname}")
            continue

        safe_fname = sanitize_name(fname)
        if safe_fname != fname:
            log.info(f"  ✏  Name sanitized: '{fname}'  →  '{safe_fname}'")

        dest = os.path.join(local_path, safe_fname)

        # Handle name collision
        if os.path.exists(dest):
            stem, ext = os.path.splitext(safe_fname)
            counter = 1
            while os.path.exists(dest):
                dest = os.path.join(local_path, f"{stem}_{counter}{ext}")
                counter += 1

        log.info(f"  ⬇  Downloading: {fname}  ({mime})")
        try:
            download_file(service, fid, fname, dest)
            log.info(f"  ✅ Saved: {dest}")
            downloaded_ids.add(fid)
            save_downloaded(downloaded_ids)

            if DELETE_AFTER_DOWNLOAD:
                delete_item(service, fid, fname)

        except Exception as e:
            log.error(f"  ✗  Failed: {fname} — {e}")

    # Recurse into subfolders
    for folder in subfolders:
        sub_id    = folder["id"]
        sub_name  = folder["name"]
        safe_sub  = sanitize_name(sub_name)
        if safe_sub != sub_name:
            log.info(f"  ✏  Folder name sanitized: '{sub_name}'  →  '{safe_sub}'")
        sub_local = os.path.join(local_path, safe_sub)
        process_folder(service, sub_id, sub_name, sub_local, downloaded_ids)

        if DELETE_AFTER_DOWNLOAD:
            delete_item(service, sub_id, sub_name)


# ── Entry Points ───────────────────────────────────────────────────────────────

def check_and_download(service, downloaded_ids):
    process_folder(service, FOLDER_ID, "ROOT", SAVE_DIR, downloaded_ids)
    return downloaded_ids


def run_once():
    log.info("=" * 60)
    log.info("Drive Auto-Fetcher v3")
    log.info(f"Folder ID : {FOLDER_ID}")
    log.info(f"Save to   : {SAVE_DIR}")
    log.info("=" * 60)

    service    = get_drive_service()
    downloaded = load_downloaded()

    # Always run debug first so you can see what the API returns
    debug_folder(service, FOLDER_ID)

    check_and_download(service, downloaded)
    log.info("Done.")
    log.info("=" * 60)


def run_watch():
    log.info("=" * 60)
    log.info(f"Drive Auto-Fetcher v3 — watch mode (every {CHECK_INTERVAL}s)")
    log.info(f"Folder ID : {FOLDER_ID}")
    log.info(f"Save to   : {SAVE_DIR}")
    log.info("=" * 60)

    service    = get_drive_service()
    downloaded = load_downloaded()

    # Debug once at start
    debug_folder(service, FOLDER_ID)

    while True:
        try:
            downloaded = check_and_download(service, downloaded)
        except Exception as e:
            log.error(f"Error during check: {e}")
        log.info(f"Sleeping {CHECK_INTERVAL}s…")
        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    if "--watch" in sys.argv:
        run_watch()
    else:
        run_once()
