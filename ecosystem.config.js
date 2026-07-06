// ============================================================
//  PM2 Ecosystem Config — Drive Auto-Fetcher
//
//  This file tells PM2 how to run drive_fetcher.py:
//  - Runs in watch mode (checks Drive every 60 seconds)
//  - Auto-restarts if the script crashes
//  - Saves logs to drive_fetcher.log
//  - Starts automatically when Windows boots
// ============================================================

module.exports = {
  apps: [
    {
      // Name shown in `pm2 list` and `pm2 logs`
      name: "drive-auto-fetcher",

      // Use Python to run the script
      interpreter: "python",

      // Path to your script (relative to this file)
      script: "drive_fetcher.py",

      // Run in watch mode — checks Drive every 60 seconds
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
