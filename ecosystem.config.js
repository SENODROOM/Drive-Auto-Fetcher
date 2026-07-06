// ============================================================
//  PM2 Ecosystem Config — Drive Auto-Fetcher
//
//  This file tells PM2 how to run src/drive_fetcher.py:
//  - Runs in watch mode (interval configured in config.json)
//  - Auto-restarts if the script crashes
//  - Saves logs to drive_fetcher.log / pm2_out.log / pm2_err.log
//  - Starts automatically on boot (Windows, Linux, or macOS)
// ============================================================

const fs = require("fs");
const path = require("path");

// If installer.ps1 / installer.sh had to download a self-contained Python
// (because none was found on the system), it records the exact interpreter
// path here so PM2 uses that one instead of guessing "python"/"python3".
function resolveInterpreter() {
  const pinnedFile = path.join(__dirname, ".runtime", "python_path.txt");
  if (fs.existsSync(pinnedFile)) {
    return fs.readFileSync(pinnedFile, "utf8").trim();
  }
  return process.platform === "win32" ? "python" : "python3";
}

module.exports = {
  apps: [
    {
      // Name shown in `pm2 list` and `pm2 logs`
      name: "drive-auto-fetcher",

      // Use Python to run the script ("python" on Windows, "python3" elsewhere,
      // or a pinned standalone interpreter — see resolveInterpreter() above)
      interpreter: resolveInterpreter(),

      // Path to your script (relative to this file, i.e. the repo root)
      script: "src/drive_fetcher.py",

      // Run in watch mode — checks Drive on the interval set in config.json
      args: "--watch",

      // Working directory (same folder as this file)
      cwd: __dirname,

      // If the script crashes, wait 5 seconds then restart
      restart_delay: 5000,

      // Restart up to 10 times; after that, stop trying
      max_restarts: 10,

      // Count a restart as "stable" after running for 10 seconds
      min_uptime: "10s",

      // PM2 manages its own logging — disable file watching
      watch: false,

      // Log settings
      out_file: "pm2_out.log",   // stdout → this file
      error_file: "pm2_err.log", // stderr → this file
      merge_logs: true,

      // Environment variables (add any you need here)
      env: {
        NODE_ENV: "production",
      },
    },
  ],
};
