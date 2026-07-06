"""
Google Drive Auto-Fetcher
=========================
- Downloads files from a Google Drive folder (or the whole Drive) — including subfolders
- Mirrors exact folder structure to the configured destination directory
- Sanitizes filenames — removes characters Windows forbids (? * : " < > | / \\)
- Deletes each file (and emptied folder) from Drive immediately after successful download
- Tracks downloaded files so duplicates are never re-downloaded
- Runs once, or continuously in watch mode

All user-tunable settings live in config.json at the repo root (see config.example.json).
Run `python src/configure.py` to create or update it interactively.
"""

import os
import sys
import json
import io
import re
import logging
import time
from pathlib import Path

# ─── PATHS ──────────────────────────────────────────────────────────────────────
# Resolved relative to the repo root (parent of this file's directory), not the
# process's current working directory, so the script behaves the same whether
# it's launched via PM2, Task Scheduler, or double-clicked from anywhere.
BASE_DIR         = Path(__file__).resolve().parent.parent
CONFIG_FILE      = BASE_DIR / "config.json"
CONFIG_EXAMPLE   = BASE_DIR / "config.example.json"
CREDENTIALS_FILE = BASE_DIR / "credentials.json"
TOKEN_FILE       = BASE_DIR / "token.json"
TRACKING_FILE    = BASE_DIR / "downloaded_files.json"
LOG_FILE         = BASE_DIR / "drive_fetcher.log"

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


# ── Config ──────────────────────────────────────────────────────────────────────

def load_config():
    """Load and validate config.json. Exits with a clear message if it's missing/invalid."""
    if not CONFIG_FILE.exists():
        log.error(f"config.json not found at {CONFIG_FILE}")
        log.error("Run:  python src/configure.py   (or scripts/setup.bat for full first-time setup)")
        sys.exit(1)

    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except json.JSONDecodeError as e:
        log.error(f"config.json is not valid JSON: {e}")
        sys.exit(1)

    mode = cfg.get("mode", "folder")
    if mode not in ("folder", "drive"):
        log.error(f"config.json: 'mode' must be 'folder' or 'drive', got {mode!r}")
        sys.exit(1)

    if mode == "drive":
        folder_id = "root"
        folder_label = "My Drive (entire account)"
    else:
        folder_id = str(cfg.get("folder_id", "")).strip()
        if not folder_id:
            log.error("config.json: 'folder_id' is empty but mode is 'folder'.")
            log.error("Run: python src/configure.py")
            sys.exit(1)
        folder_label = folder_id

    destination_path = str(cfg.get("destination_path", "")).strip()
    if not destination_path:
        log.error("config.json: 'destination_path' is empty. Run: python src/configure.py")
        sys.exit(1)

    return {
        "mode": mode,
        "folder_id": folder_id,
        "folder_label": folder_label,
        "destination_path": destination_path,
        "delete_after_download": bool(cfg.get("delete_after_download", True)),
        "check_interval_seconds": int(cfg.get("check_interval_seconds", 60)),
    }


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
    if TRACKING_FILE.exists():
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

    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)

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
            if not CREDENTIALS_FILE.exists():
                log.error(f"credentials.json not found at {CREDENTIALS_FILE}! See README.md.")
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file(str(CREDENTIALS_FILE), SCOPES)
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
        if folder_id != "root":
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

def process_folder(service, folder_id, folder_name, local_path, downloaded_ids, delete_after_download):
    """
    Recursively download all files in a Drive folder to local_path.
    Mirrors the exact folder structure.
    Deletes each file from Drive immediately after download (if enabled).
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

            if delete_after_download:
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
        process_folder(service, sub_id, sub_name, sub_local, downloaded_ids, delete_after_download)

        if delete_after_download:
            delete_item(service, sub_id, sub_name)


# ── Entry Points ───────────────────────────────────────────────────────────────

def check_and_download(service, downloaded_ids, config):
    process_folder(
        service,
        config["folder_id"],
        config["folder_label"],
        config["destination_path"],
        downloaded_ids,
        config["delete_after_download"],
    )
    return downloaded_ids


def run_once():
    config = load_config()

    log.info("=" * 60)
    log.info("Drive Auto-Fetcher")
    log.info(f"Source    : {config['folder_label']}")
    log.info(f"Save to   : {config['destination_path']}")
    log.info(f"Delete after download : {config['delete_after_download']}")
    log.info("=" * 60)

    service    = get_drive_service()
    downloaded = load_downloaded()

    # Always run debug first so you can see what the API returns
    debug_folder(service, config["folder_id"])

    check_and_download(service, downloaded, config)
    log.info("Done.")
    log.info("=" * 60)


def run_watch():
    config = load_config()

    log.info("=" * 60)
    log.info(f"Drive Auto-Fetcher — watch mode (every {config['check_interval_seconds']}s)")
    log.info(f"Source    : {config['folder_label']}")
    log.info(f"Save to   : {config['destination_path']}")
    log.info(f"Delete after download : {config['delete_after_download']}")
    log.info("=" * 60)

    service    = get_drive_service()
    downloaded = load_downloaded()

    # Debug once at start
    debug_folder(service, config["folder_id"])

    while True:
        try:
            downloaded = check_and_download(service, downloaded, config)
        except Exception as e:
            log.error(f"Error during check: {e}")
        log.info(f"Sleeping {config['check_interval_seconds']}s…")
        time.sleep(config["check_interval_seconds"])


def run_auth_only():
    """Perform the OAuth login (and save token.json) without downloading anything."""
    log.info("Running authentication only (no download)...")
    get_drive_service()
    log.info(f"Authentication successful. Token saved to {TOKEN_FILE}")


if __name__ == "__main__":
    if "--auth-only" in sys.argv:
        run_auth_only()
    elif "--watch" in sys.argv:
        run_watch()
    else:
        run_once()
