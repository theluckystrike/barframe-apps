# ReminderVault
Universal sandboxed macOS menu bar Markdown ↔ EventKit Reminders sync.
Build and validate with `python3 -I ../../kit/gate.py .`.
Core Swift Testing coverage exercises parsing, exact unrelated-line preservation, date validation, and conflict decisions. Sample mode requires no account or credentials; optional live EventKit and provider propagation checks need permissions for user-selected test data. Screenshots are rendered from the actual SwiftUI panel using bundled Sample tasks. The custom icon is drawn with Core Graphics.

Decisions: stable rv HTML comment IDs; append imports to ReminderVault Inbox.md; new tasks use the alphabetically first selected list; compare Markdown file mtime against reminder lastModifiedDate only when both sides diverge from baseline; equal timestamps favor Markdown; never propagate deletions. Revalidate vault text and remote mapped fields before apply. Stop automatic sync on failure and require a new preview. Sample data is isolated. Local baseline writes occur after each committed reminder for retry recovery. No subscription; listing price $4.99.

Imported titles escape backslashes and date symbols to keep literal date-token text intact. Previews show file/list/task identity and both old values plus the proposed mapped fields. Preview failures revoke session approval. Privacy Policy opens bundled storage and deletion details; the hosting owner still needs to update the retained public page.
