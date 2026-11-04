# ReminderVault Privacy Policy
Updated 14 October 2026. Developer and seller: Michael Lip.

ReminderVault reads and writes Markdown tasks in the vault folder you select and tasks in the writable Apple Reminders lists you select. A security-scoped bookmark retains permission to the chosen folder. EventKit asks for Reminders access. The app does not request calendar-event access.

Task processing happens locally on your Mac. Michael Lip does not collect, receive, transmit, sell, or share task content, identifiers, diagnostics, or personal data. There are no developer accounts, analytics, ads, tracking, or app-operated sync servers. Opening a public support or policy page uses your browser and that website's normal hosting services. Your existing vault storage provider and your Apple Reminders account may sync data independently under their own privacy policies.

Local storage and retention
The app's sandbox container stores task baselines (titles, completion and due dates) in sync-state.json. Preferences retain the vault bookmark, selected list IDs, task-to-reminder ID links, sync interval, last-sync time, and the latest saved conflict-log entries. Logs can contain task titles and conflict decisions; the saved log retains up to 200 entries. Baselines and settings remain until you delete them. Sample mode copies example Markdown into the container's SampleVault folder and never writes to EventKit. Stable rv identifier comments remain in your selected Markdown files and reminder notes. The app does not propagate task deletions.

Stop access and delete local data
Quit ReminderVault to stop syncing. Revoke Reminders permission in System Settings → Privacy & Security → Reminders. To revoke saved folder access and remove the app's local state, quit the app, open Finder → Go → Go to Folder, and open ~/Library/Containers/com.michaellip.remindervault/Data/. Delete sync-state.json and SampleVault if present, and delete Library/Preferences/com.michaellip.remindervault.plist. You can instead remove the entire ReminderVault container after quitting to clear all app-local data. Removing the app alone may leave its container behind. These steps do not delete tasks in your vault or Reminders. If desired, remove the app's <!-- rv:... --> identifier comments from those tasks manually. Launch at login can be disabled in Settings or System Settings → General → Login Items.

On the next launch, choose the folder and lists again and review a preview before applying sync. Deleting local state resets conflict history and pairing baselines; review task pairings carefully before reconnecting existing data. Automatic sync approval is session-only and stops after preview or sync failure.

Questions: support@barframe.com. This bundled policy is available without a network connection.
