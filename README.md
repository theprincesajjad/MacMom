# Appfold

Appfold is a free, open-source menu-bar activity monitor for macOS. It shows apps, not a flat process list. Helpers that live in an app bundle, and processes that app launched, count toward that app. An unrelated app stays separate. A process that belongs to no app is still listed.

The menu-bar item shows live CPU. Opening it, or the main window, shows system-wide CPU, memory, disk, and network with the apps behind those figures. Choose an app to see its processes. Quit asks a process or a whole app to exit. Force Quit ends it immediately. Neither runs until you confirm.

Usage history stays on this Mac for 30 days (`~/Library/Application Support/Appfold/history.jsonl`). You can read the last 12 hours, 24 hours, 7 days, and 30 days. Samples older than 30 days are deleted. A sustained high CPU, a sustained memory climb, and heavy disk or network show a local alert. Quiet apps do not. No account, license key, or network service is required.

## Light on purpose

The app is a small AppKit program. It does not ship a browser or a web view. With the main window closed it samples every 5 seconds. With the window open it samples about once a second. Per-process CPU, memory, disk, and energy come from the counters macOS already exposes. Per-process network bytes are not available to a normal unsandboxed app, so that column stays at zero instead of showing an invented number. System network is the traffic counted on this Mac's interfaces.

## Build and run

Requires macOS 13 or later.

```bash
swift test
Scripts/package-app.sh
open .build/Appfold.app
```

The package script builds a release `Appfold.app` and ad-hoc signs it so Launch Services will open it. The app is not sandboxed, because a sandbox cannot see other apps' processes.

## License

[MIT](LICENSE). Use it, change it, and share it without an account or a fee.
