"""
Interactive setup wizard for Drive Auto-Fetcher.

Asks the user what to fetch (a specific folder or the whole Drive), where to
save it, and how it should behave, then writes config.json at the repo root.

Usage:
    python src/configure.py
"""

import json
import os
import re
import sys
from pathlib import Path

BASE_DIR    = Path(__file__).resolve().parent.parent
CONFIG_FILE = BASE_DIR / "config.json"

FOLDER_URL_RE = re.compile(r"[-\w]{25,}")


def default_destination():
    """A sensible per-OS starting suggestion; the user can type anything else."""
    if os.name == "nt":
        return "D:/Youtube"
    return str(Path.home() / "GoogleDrive")


def ask(prompt, default=None):
    suffix = f" [{default}]" if default is not None else ""
    answer = input(f"{prompt}{suffix}: ").strip()
    return answer if answer else default


def ask_yes_no(prompt, default=True):
    default_label = "Y/n" if default else "y/N"
    while True:
        answer = input(f"{prompt} [{default_label}]: ").strip().lower()
        if not answer:
            return default
        if answer in ("y", "yes"):
            return True
        if answer in ("n", "no"):
            return False
        print("Please answer 'y' or 'n'.")


def extract_folder_id(raw):
    """Accept either a bare folder ID or a full Drive URL and return just the ID."""
    raw = raw.strip()
    match = FOLDER_URL_RE.search(raw)
    return match.group(0) if match else raw


def load_existing():
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None
    return None


def main():
    print("=" * 60)
    print("  Drive Auto-Fetcher — Configuration Wizard")
    print("=" * 60)

    existing = load_existing()
    if existing:
        print("\nAn existing config.json was found:")
        print(json.dumps(existing, indent=2))
        if not ask_yes_no("\nOverwrite it?", default=False):
            print("Keeping existing config.json. Nothing changed.")
            return

    print("\nWhat do you want to fetch?")
    print("  1) A specific Drive folder")
    print("  2) My entire Google Drive (everything you own or can access)")
    choice = ask("Enter 1 or 2", default="1")

    if choice.strip() == "2":
        mode = "drive"
        folder_id = ""
        print("\nMode set to: whole Drive.")
    else:
        mode = "folder"
        print("\nOpen the folder in Google Drive and copy its URL or ID.")
        print("Example URL: https://drive.google.com/drive/folders/1iPZHhDGWwe3outDkz467pkgTkSCYN2Kw")
        raw = ask("Paste the folder URL or ID")
        while not raw:
            raw = ask("Paste the folder URL or ID")
        folder_id = extract_folder_id(raw)
        print(f"Using folder ID: {folder_id}")

    print("\nWhere should downloaded files be saved on this machine?")
    default_dest = existing.get("destination_path") if existing else default_destination()
    destination_path = ask("Destination folder", default=default_dest)
    destination_path = destination_path.replace("\\", "/")

    print("\nDelete each file from Google Drive right after it downloads successfully?")
    print("(If 'no', files stay in Drive and will be skipped on future runs once downloaded.)")
    delete_after_download = ask_yes_no("Delete after download?", default=True)

    print("\nIn watch mode, how often should it check Drive for new files (seconds)?")
    interval_raw = ask("Check interval (seconds)", default="60")
    try:
        check_interval_seconds = max(10, int(interval_raw))
    except ValueError:
        check_interval_seconds = 60

    config = {
        "mode": mode,
        "folder_id": folder_id,
        "destination_path": destination_path,
        "delete_after_download": delete_after_download,
        "check_interval_seconds": check_interval_seconds,
    }

    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
        f.write("\n")

    print("\n" + "=" * 60)
    print(f"Saved: {CONFIG_FILE}")
    print(json.dumps(config, indent=2))
    print("=" * 60)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled.")
        sys.exit(1)
