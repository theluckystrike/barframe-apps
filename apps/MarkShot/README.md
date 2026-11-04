# MarkShot

Sandboxed menu bar capture and native annotation for system version 14.0 or newer. Uses ScreenCaptureKit and requires Screen Recording permission for live captures. Open Sample editor from the menu for the bundled synthetic image without permission.

Build and verify with `python3 -I ../../kit/gate.py .`. The package contains Swift Testing core tests. `scripts/make_assets.swift` draws the custom icon and synthetic sample using Core Graphics and native text rendering. --screenshots renders three native Sample screenshots. --smoke verifies runtime PNG, clipboard, bookmark, and crop behavior in the sandbox.

Annotations export as flattened PNG. History stores ten captures; edits update history on copy, save, or drag. Settings supports a bookmarked folder, configurable Carbon global shortcut, and optional SMAppService launch at login.
