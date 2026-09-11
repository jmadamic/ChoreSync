# HouseholdApp

Household app for any number of people, built with **SwiftUI + Firebase** (Cloud Firestore + Firebase Auth, project ID `jordan-code`). Jordan and his wife use it daily — **never make changes that could wipe or orphan household data.**

Seven tabs, order configurable per device (Settings → Tab Order): **Chores**, **Shopping**, **Meals**, **Garden**, **Packing**, **Looking For**, **Settings**. iOS shows the first four; the rest go under an automatic More tab.

## Build & Run

```bash
# Regenerate Xcode project (required after adding/removing Swift files)
xcodegen generate

# IMPORTANT: xcodegen overwrites the entitlements file — restore after every generate
git checkout -- HouseholdApp/HouseholdApp.entitlements

# Build for simulator
xcodebuild -project HouseholdApp.xcodeproj -scheme HouseholdApp -sdk iphonesimulator -destination 'id=4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF' build

# Install and launch
xcrun simctl install 4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF <path-to-built-.app>
xcrun simctl launch 4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF com.householdapp.app

# Build for real devices (free personal team JBZQM9YC55 — per-device destination
# with device registration; generic/platform=iOS may miss devices on the profile)
xcodebuild -project HouseholdApp.xcodeproj -scheme HouseholdApp \
  -destination 'platform=iOS,id=<ECID>' -configuration Debug \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

# Install on a device (must be unlocked)
xcrun devicectl device install app --device <UDID> <path-to-built-.app>

# Deploy Firestore security rules (firestore.rules is the source of truth)
firebase deploy --only firestore:rules
```

`scripts/refresh-sideload.sh` runs the device rebuild/reinstall weekly via launchd (free-team apps expire every 7 days). Device IDs live in that script.

## Key Conventions

- **xcodegen**: `project.yml` is the source of truth. Never edit `HouseholdApp.xcodeproj` by hand. Restore the entitlements file after every generate.
- **Firestore-first**: All shared data is Codable `*Doc` structs + `*Store` observable classes in `HouseholdApp/Firebase/`. Each store opens a snapshot listener in `HouseholdAppApp.startStores` and exposes `save`/`delete` (guard against empty `householdId`).
- **New subcollections need rules**: add a member-only `match` block in `firestore.rules` AND deploy it (`firebase deploy --only firestore:rules`) — a listener that starts before rules allow it fails with "Missing or insufficient permissions" and does not retry until app restart.
- **Backward-compatible model changes only**: new fields on `*Doc` structs must be optional with a default value so existing Firestore documents still decode and old app builds keep working. No migrations.
- **@AppStorage for device-local settings**: store lists, item-type lists, icon mappings, and notification prefs live in `AppSettings.swift` (JSON-encoded strings). Member names are the exception — they sync via `memberNames` on the household doc.
- **Multi-member support**: household supports N members. Assignment is `assignedToMembers: [Int]` (member indices); empty = Everyone.
- **Filter bars**: "All" + one tab per member. Filtering shows items with empty `assignedToMembers` OR containing the selected index.
- **Row conventions**: 44 pt check-button tap targets, haptic on toggle, VoiceOver summary via `.accessibilityLabel`, `.caption2` (never fixed point sizes).
- **Auto-cleanup**: completed chores, purchased items, past meals, trips ended >1 week ago (cascading to their packing items), and fully-harvested plants are deleted once per session on first snapshot (`hasCleanedUp` flag in each store). Saved meals and wishes are long-lived and never auto-cleaned.
- **Cross-tab links**: `TabRouter` (in `RootView.swift`) owns tab selection, keyed by `AppTab` rawValue so it survives reordering; `router.openMeal(id)` jumps to the Meals tab and opens a meal.
- **Adding a tab**: add an `AppTab` case (never rename existing raw values — they're persisted), a `tabContent` branch, the store in `HouseholdAppApp`, a rules block, and the Settings count + delete-all entry.
- **Prefilled forms**: several flows hand a draft document to an existing form (`ShoppingFormView(item:isPrefilledDraft:)`, `ChoreFormView(chore:isPrefilledDraft:)`, `MealFormView(meal:template:)`). The flag only affects the title — the draft's unused ID means `setData` creates rather than updates.
- **Notification IDs are prefix-scoped** (`hh-chore-`, `hh-shop-`). Bulk reschedules must remove by prefix — `removeAllPendingNotificationRequests()` would wipe the other kind.
- **Docs are part of every push**: update BOTH `README.md` (features table, project structure, data model) and `CLAUDE.md` (conventions, architecture, new gotchas) in the same PR as the code. Not "when structure changes" — every push. CLAUDE.md loads into context each session, so drift there silently misleads future work; it went stale for ~10 features before being caught.
- **GitHub**: Push changes as PRs on feature branches (repo: jmadamic/HouseholdApp), merge after verifying in the simulator.
- **Commit messages via file**: write the message to a file and use `git commit -F <file>`. Heredoc commits repeatedly break the permission stream in this environment.
- **Signing resets after `xcodegen generate`**: regenerating the project drops the Xcode signing session, so CLI device builds fail with "No Account for Team". Only a **Run from the Xcode GUI** restores it — the CLI cannot. A failed build leaves a stale binary in DerivedData, so **never install after a failed build**; `devicectl` will report success while shipping the old app.

## Architecture

- **Auth** (`AuthController`): anonymous Firebase sign-in on first launch; optional Google Sign-In upgrade links the account and keeps the same UID.
- **Household** (`HouseholdController` + `HouseholdDoc`): all data lives under `/households/{id}` with subcollections `chores`, `categories`, `completions`, `shoppingItems`, `meals`, `savedMeals`, `trips`, `packingItems`, `gardenPlants`, `wishes`. **Every one must also be added to `deleteHousehold`'s cascade list** — Firestore doesn't cascade, and anything missed is orphaned unreachable once the household doc is gone. Access = `request.auth.uid ∈ memberIds`, enforced by `firestore.rules`. Join via 6-char invite codes at `/invites/{code}`. A permission error or UID missing from `memberIds` triggers stale-household recovery (clear cached ID, auto-create).
- **Meal ↔ grocery link**: grocery items created from a meal's missing ingredients carry `mealId`/`mealName`; the shopping row shows a badge that routes back to the meal.
- **Notifications** (`NotificationManager`): local-only reminders for chore due dates AND shopping need-by dates — 9 am day-of / day-before, or at the item's own time when one is set. Rescheduled on every relevant snapshot and settings change. No APNs entitlement — free personal teams can't provision it, so there are no cross-device pushes (that would need Cloud Functions on the paid Blaze plan).
- **Repeat logic**: completing a repeating chore advances its due date (rolling model) and writes a `CompletionLogDoc`; non-repeating chores archive in place. Beyond the presets, `RepeatInterval.customEvery` / `.customWeekday` read a `CustomRepeatRule` on the chore ("every 6 months", "third Tuesday every month"); always advance via `chore.nextDueDate(from:)`, never `RepeatInterval.nextDate` alone.
- **Garden ↔ shopping**: `GardenPlantDoc` holds a list of `PlantHarvest` (date + amount) or an `isAlwaysReady` flag for herbs. Legacy single-harvest fields are mirrored on every save (`syncLegacyFields`) so older builds still work. Shopping rows show a "Growing" hint via `GardenStore.readySoonPlant(matching:)`, and the item form opens `ReadySoonView`.
- **Looking For** (`WishDoc`): collaborative research — must-have/nice-to-have criteria, dated notes attributed by member index, links. Note editing is gated on the device's "I am" setting: a UI convenience, **not** a security boundary (rules are household-scoped).
- **Spreadsheet import** (`XLSXReader` + `MealPlanImporter` + `MealPlanImportView`): the bundled `Resources/MealPlanTemplate.xlsx` is generated by `scripts/make-meal-template.py` (openpyxl) — **regenerate it and update the importer's header aliases together** when columns change. `XLSXReader` is a deliberate zero-dependency reader (zip central directory + Apple `Compression` raw-deflate + `XMLParser`); it does not support zip64 or encrypted files, which spreadsheet apps never produce at this size. The importer never fails a whole file: each row yields documents or an `ImportIssue` with sheet + row, and duplicates against existing meals/items/trips are skipped so re-import is idempotent. Writes happen only from the preview's Import button, in dependency order (trips → meals → shopping → packing).
- **Meal ingredients → shopping**: the cart toggle on an ingredient sets `have = false`; shopping items are created **at save time only** (`createShoppingItems`) and flagged `addedToList`. Never write shopping items mid-edit — cancelling the form would orphan them.
- **Voice entry** (`SpeechCapture` + `VoiceIntentParser`): on-device speech, then a rules parser extracts kind/date/time/assignee and prefills a form for confirmation. Parsing sits behind `VoiceIntentParsing` so a model-backed parser can replace it; Apple Foundation Models were rejected because they need Apple Intelligence hardware (iPhone 15 Pro+) and one household phone is a 12 Pro.
- **Edit pattern**: categories, stores, and item types have dedicated form views (`CategoryFormView`, `StoreFormView`, `ItemTypeFormView`) with name, icon picker, and delete; parents pass `onDelete`/`onSave` callbacks. `CategoryFormView.iconOptions` is the shared SF Symbol list.
