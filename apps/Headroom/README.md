# Headroom Agent Memory

Reduced sandbox port. See ../../review/headroom-sandbox.md for measured API restrictions. Bundle ID com.michaellip.headroom. macOS 14 minimum; universal arm64/x86_64. Build and check: `python3 -I ../../kit/gate.py .` from this directory. The kit signs locally, launches through LaunchServices, produces three native SwiftUI screenshots, and runs Swift Testing plus sandbox smoke checks. Launch with --sample for synthetic data. The HR menu-bar item opens the dashboard.

Capacity = floor(max(0, available GiB - 4 GiB) / chosen agent budget). A failed memory probe yields unavailable. Swap use or non-normal pressure yields zero. This is a planning estimate, not a prediction that future workloads cannot swap. Resident memory is not used as physical footprint or as the per-agent budget. It may double-count shared pages and excludes compressed pages. Detection is conservative and can miss agents. No process metadata is persisted or transmitted. The custom icon consists of original geometric bars.

The app is a new reduced implementation based on observed behavior of the owner's Headroom probes; source inputs were left unchanged. No distribution signing or submission has occurred. {BRAND} and {DOMAIN} must be finalized before submission.
