# NativeLedger Privacy Policy

Michael Lip provides NativeLedger. NativeLedger works on your Mac. It has no account, analytics, advertising or server. The app makes no network connections and does not upload ledgers or inspection results.

## Folders and apps you choose

You choose a folder to watch, or a single app, with the system file picker. NativeLedger saves a read-only, app-scoped bookmark for each folder and app you choose. In a watched folder, it looks for apps in the folder and one level below. It does not read other folders on your Mac. While NativeLedger is open, it watches the chosen folders for changes. It stops watching when you quit it.

## What NativeLedger reads

For each app, NativeLedger reads the bundle identifier, name, version, build, minimum system version and update feed address from the app's Info.plist. It reads the privacy usage description texts that the app declares. It reads the names of the login items, launch agents, launch daemons, XPC services and helpers inside the app bundle. It reads the signing identifier, signing team, declared entitlements and code directory hash (cdhash) that macOS reports. It reads the main executable to find its architecture slices and to calculate its SHA-256. It asks macOS to check the validity of the code signature.

To notice a change, NativeLedger reads the size, modification time and file number of a few files in each app bundle. NativeLedger does not launch the apps it reads. It does not read their documents or data.

## Saved ledgers

Ledgers are saved in ledgers.json inside the app's sandbox container. A ledger contains the app name, its saved bookmark and a list of dated entries. Each entry contains the values above. This includes the hashes, the usage description texts, the background item names and the update feed address of each app. An entry also contains the detected changes, the anomaly flags, acknowledgements and the entry hashes. The bookmarks for watched folders are also saved inside the container.

If ledgers.json cannot be read, NativeLedger pauses changes and does not overwrite it. Start fresh copies the unreadable file to a dated recovery file in the same folder before it starts again.

## Exported ledger files

Export Ledger writes a .nativeledger file to the location you choose in the save panel. It writes the file nowhere else. The file contains the app names and ledger entries with the values above. It contains no file paths and no bookmarks. NativeLedger does not send the file anywhere. You decide where the file goes and who receives it.

## Opened ledger files

Compare with Ledger File reads the file you choose in the open panel to show the comparison. NativeLedger does not change the file. It does not store the file or its contents.

## Notifications

Alerts are off by default. If you turn them on in Settings, macOS asks you for permission to show notifications. NativeLedger then shows local notifications on your Mac. A notification names the app and the anomaly and contains no file paths. Notifications are not sent to a server.

## Sample

Sample uses synthetic ledgers. Sample data is kept in memory and is never saved. Sample does not change your saved ledgers.

## Deleting your data

To delete the ledger of one app, select the app and choose Remove. Remove deletes the ledger and its saved bookmark. To delete all NativeLedger data, quit NativeLedger and delete its folder in Library, Containers in your home folder. The folder is named NativeLedger or com.michaellip.nativeledger. Deleting the app itself does not delete this folder. Exported files and recovery copies stay where they are until you delete them.

## Links

The privacy and support links in Settings open these pages in your default browser. The website receives the normal browser request.

For help, use the support link on the App Store product page. This bundled copy is available offline.
