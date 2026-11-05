# NativeLedger Support

## Getting started

Choose Watch a Folder and select the folder that holds your apps, for example Applications. NativeLedger finds the apps in that folder and one level below and records an opening entry for each. To track a single app, choose Add App and select it. Choose Open Sample to explore synthetic ledgers. Command-comma opens Settings.

Apps that come with macOS are in the system Applications folder. To watch them, choose Watch a Folder, press Command-Shift-G, type /System/Applications and choose Open.

## Automatic recording

While NativeLedger is open, it watches the chosen folders. When an app in a watched folder changes, NativeLedger reads it again a few seconds later. If anything differs from the previous entry, it appends a new entry. If nothing changed, no entry is added. When you open NativeLedger, it records what changed while it was closed. A new app gets its own ledger. A removed app gets a final Removed entry and stays in the list.

## What each entry records

Each entry records the bundle identifier, version, build, architecture slices, minimum system version, signing identifier, signing team and declared entitlements. It records the code directory hash (cdhash) and the SHA-256 of the main executable. It records the privacy usage descriptions, the update feed address and the background items by name. Background items are login items, launch agents, launch daemons, XPC services and helpers inside the app. The signature validity result is Valid, Invalid with an error code, Not signed or Not checked.

## Recent changes

Recent changes at the top of the sidebar lists the entries from all ledgers in the last seven days. The newest entry is at the top. Red chips mark anomalies.

## Anomalies

A red chip marks an anomaly. Silent rebuild means the executable or cdhash changed and the version and build did not change. Version regression means the version is lower than in the previous entry. Team change means the signing team changed. New background item means the app has a new login item, launch agent, launch daemon, XPC service or helper. New privacy usage means the app declares a privacy usage description that the previous entry did not have.

Signature invalid means the code signature did not pass the macOS validity check for all architectures. Update feed changed means the update feed address differs from the previous entry. New entitlement and Architecture change are marked as well. Versions are compared by number, so 1.10 is higher than 1.9. A version that is not numeric never produces a version regression.

## Verify chain

Each entry stores the SHA-256 of the entry before it. Choose Verify chain to recalculate the hashes. Intact means every entry matches. Broken names the earliest entry that does not match.

## What a broken chain means

A broken chain means the saved ledger changed outside NativeLedger. An entry was edited, removed or reordered, or the file was damaged. It does not mean that the app is unsafe. The sidebar badge reads Chain broken. Compare the ledger with an exported copy to see what changed. To start a clean ledger for the app, choose Remove and add the app again.

The chain cannot show that the newest entries were removed or that the whole file was rewritten. Export your ledgers from time to time and keep the files in a safe place.

## Acknowledge

Choose Acknowledge after you review the latest entry. NativeLedger reads the app again and records your acceptance as a new entry in the chain. If the app changed since the latest entry, NativeLedger records the change instead, so you can review it before you acknowledge. The sidebar badge shows Intact, Anomaly, Chain broken, Not inspected, Unavailable or Removed.

## Export and compare

Choose Export Ledger and select where to save the .nativeledger file. The file contains no file paths and no bookmarks. On a different Mac, choose Compare with Ledger File and open that file. NativeLedger compares the newest entry for each bundle identifier. Same build means the version, the build and the hashes match. Different binary for the same version means the version matches and the binary does not. Different version means the versions differ. Only on this Mac and Only on the other Mac mean that the app is missing from one of the ledgers.

## Alerts

Alerts are off by default. In Settings, turn on Alert me about high-severity changes. NativeLedger then shows a notification when an automatic entry has Signature invalid, Team change or New background item.

If no notification appears, open System Settings and choose Notifications. Select NativeLedger and turn on Allow notifications. If you denied permission earlier, NativeLedger cannot ask again, so change it in System Settings.

## Renew access

If NativeLedger loses access to an app or a folder, the badge reads Unavailable and the earlier entries stay visible. This can happen after you move or rename the folder or app. To renew access to an app, choose Add App and select the same app again. NativeLedger keeps its ledger and adds no duplicate. To renew access to a folder, choose Watch a Folder and select the folder again.

## If saved data cannot be read

If ledgers.json cannot be read, NativeLedger pauses changes and shows Retry saved data and Start fresh (keeps a copy). If you can restore the file from a backup, restore it and choose Retry saved data. Start fresh copies the unreadable file to a dated recovery file in the same folder and starts with no ledgers. After Start fresh, watch your folders again. To compare with the old data, use an exported ledger file.

## Limits

NativeLedger records changes while it is open. It reads the folders and apps you choose and nothing else. The signature check uses the macOS code signing check. A valid signature means the app matches its signature. It does not mean that the app is safe. NativeLedger is not malware detection and gives no safety verdict. It does not inspect the code inside nested items, effective permissions or network traffic. It does not download or install updates.

## Settings and removal

Settings sets the age after which an inspection counts as stale, and turns alerts on or off. Remove deletes a ledger and its saved access. Settings also has the privacy and support links.

For help, open an issue at https://github.com/theluckystrike/barframe-apps/issues or email support@barframe.com. This bundled guide is available offline.
