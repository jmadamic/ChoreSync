# HouseholdApp

A household chore, shopping, and meal-planning app for **any number of people**, built with **SwiftUI + Firebase**.
Data lives in **Cloud Firestore** and syncs in real time between everyone in the household. Sign-in is invisible — the app starts with an anonymous Firebase account and can be upgraded to Google Sign-In for cross-device recovery.

---

## Features

| Feature | Details |
|---|---|
| **Categories** | Group chores into colour-coded, icon-tagged buckets (Kitchen, Bathroom, Outdoor, etc.) |
| **Assignments** | Multi-select any combination of household members per chore, item, or meal — "Select All" sets to Everyone |
| **Due dates** | Pick a specific date (optionally with a time), any week, any month, or no due date — supports future weeks and months |
| **Repeating chores** | Daily, weekly, bi-weekly, monthly, or yearly — chore resets automatically after completion |
| **Completion tracking** | Per-person history stored for every completion |
| **Household sharing** | One person creates the household; others join with a 6-character invite code from Settings. Changes sync to every device in real time |
| **Shared member names** | Member names are stored on the household document, so renaming someone updates every device |
| **Shopping list** | Separate tab for groceries/household items — group by store or by type, with assignee support. Stores and item types are fully editable with custom icons. Items can carry an optional "need by" date/time that reminds whoever they're assigned to |
| **Packing lists** | Create trips/events with dates and pack per-section (Clothing, Food, Toiletries, custom…). Meals tied to a trip auto-add their ingredients to the Food section; chores can be tied to a trip too (e.g. "turn off water heater before leaving") |
| **Meal planning** | Plan meals by day and type (breakfast, brunch, lunch, dinner, snack, dessert) with an optional dish name and assigned cook(s). Track ingredients you have vs. need — missing ones can be added to the grocery list in one tap, and each grocery item links back to its meal. Meals auto-complete once their day passes (no checkbox). Attach a recipe link and/or typed instructions |
| **My Meals library** | Save any meal for repeated use, then plan it again with one tap (prefills ingredients, recipe, instructions). Share a meal — full details as text — via the standard share sheet |
| **Garden** | Track what you're growing with multiple harvests per plant, each with its own date and amount ("2 zucchinis", "some raspberries") — or mark herbs as "always ready" to pick as needed. Shopping-list items matching a crop that's ready (or close) show a "Growing" hint with the expected amount so you can hold off buying, and the add-item form has a "See what's ready soon" browser listing everything ripening in the next two weeks. Gardening chores appear in both the Chores tab and the Garden tab |
| **Looking For** | A collaborative wishlist for things you're researching (a new bed, a dishwasher). Track must-haves vs nice-to-haves, dated research notes attributed to whoever wrote them (you can edit your own), and links. When you decide, "Add to Shopping List" prefills a shopping item from what you've gathered |
| **Plan from a spreadsheet** | Meals tab → table icon. Share the bundled Excel/Google Sheets template, fill in meals (plus optional Trips and Packing sheets), import the .xlsx back. Preview shows exactly what will be created; rows with problems are listed by sheet and row number and simply left out. Creates meals, shopping items for "to buy" ingredients, missing trips, and packing items. Re-importing the same file is safe — existing items are skipped |
| **Voice entry** | Tap the mic on Chores or Shopping and say what you need — *"add task due tomorrow to clean the bathroom"*. Speech is transcribed on-device, parsed for the date, time, and assignee, then prefills the normal form for you to confirm |
| **Local notifications** | Due-date reminders for chores and need-by reminders for shopping items at 9 am — or at the item's own time when one is set (day-of and/or day-before), filterable to my/shared/all in Settings |
| **Auto-cleanup** | Completed chores, purchased items, past meals, ended trips, and harvested plants are deleted automatically after 1 week |
| **Easy UI** | Swipe to complete or delete; tap to edit; colour-coded urgency sections; VoiceOver labels and 44 pt tap targets throughout |

---

## Requirements

- **Xcode 16+** (free from the Mac App Store)
- **iOS 17+** on the target device(s)
- A **Firebase project** (free Spark plan is enough — this app uses only Firestore + Auth)
- An **Apple ID** for code signing — a free personal team works, but apps expire after 7 days and must be re-installed weekly (see `scripts/refresh-sideload.sh`). A paid Apple Developer membership removes the weekly expiry.

---

## Project Structure

```
HouseholdApp/
├── project.yml                         ← xcodegen config — re-run to regenerate .xcodeproj
├── firestore.rules                     ← Firestore security rules (deploy with firebase CLI)
├── firebase.json / .firebaserc         ← Firebase CLI config (project: jordan-code)
├── scripts/refresh-sideload.sh         ← Weekly rebuild + reinstall for free-team signing
├── HouseholdApp.xcodeproj/             ← generated by xcodegen — do not edit by hand
└── HouseholdApp/
    ├── App/
    │   ├── HouseholdAppApp.swift       ← @main entry point; wires stores + starts listeners
    │   └── AppSettings.swift           ← Observable wrapper for UserDefaults (names, stores, item types, icons, notification prefs)
    │
    ├── Firebase/
    │   ├── AuthController.swift        ← Anonymous sign-in on first launch; optional Google upgrade
    │   ├── HouseholdController.swift   ← Create/join/leave household; invite codes; member names
    │   ├── HouseholdDoc.swift          ← /households/{id}: memberIds, ownerId, inviteCode, memberNames
    │   ├── ChoreDoc.swift + ChoreStore.swift
    │   ├── CategoryDoc.swift + CategoryStore.swift
    │   ├── CompletionLogDoc.swift
    │   ├── ShoppingItemDoc.swift + ShoppingStore.swift
    │   ├── MealDoc.swift + MealStore.swift
    │   ├── SavedMealDoc.swift + SavedMealStore.swift    ← "My Meals" reusable library
    │   ├── TripDoc.swift + TripStore.swift              ← Trips/events for packing
    │   ├── PackingItemDoc.swift + PackingStore.swift
    │   ├── GardenPlantDoc.swift + GardenStore.swift     ← Plants, harvests, always-ready herbs
    │   └── WishDoc.swift + WishStore.swift              ← "Looking For" research items
    │
    ├── Models/
    │   ├── Enums.swift                 ← DueDateType, RepeatInterval, ChoreSection
    │   └── MemberAssignment.swift      ← Everyone / member-index assignment helper + colours
    │
    ├── Utilities/
    │   ├── XLSXReader.swift            ← Dependency-free .xlsx reader (zip + Compression + XMLParser)
    │   ├── MealPlanImporter.swift      ← Spreadsheet rows → meals/shopping/trips/packing plan with row-level issues
    │   ├── SpeechCapture.swift         ← On-device speech-to-text (SFSpeechRecognizer)
    │   ├── VoiceIntentParser.swift     ← Turns a transcript into a draft chore / shopping item
    │   ├── Color+Hex.swift             ← Color ↔ "#RRGGBB" hex string conversion
    │   ├── IconView.swift              ← Shared icon + label components
    │   └── NotificationManager.swift   ← Local due-date reminders (UNUserNotificationCenter)
    │
    └── Views/
        ├── RootView.swift              ← TabView: Chores | Shopping | Meals | Garden | Packing | Looking For | Settings (order configurable) (+ TabRouter for cross-tab links)
        ├── Auth/                       ← Sign-in and household setup screens
        ├── ChoreList/ + ChoreForm/     ← Chore list, rows, add/edit sheet
        ├── Categories/                 ← Category grid and add/edit form
        ├── Shopping/                   ← Shopping list, rows, item/store/type forms
        ├── Garden/                     ← Growing plants with ready dates, garden chores
        ├── Wishes/                     ← "Looking For" list: criteria, dated notes, links
        ├── Voice/                      ← Mic capture + confirm screen for spoken entry
    ├── Resources/
    │   └── MealPlanTemplate.xlsx       ← Spreadsheet template (regenerate with scripts/make-meal-template.py)
        ├── Packing/                    ← Trip list, trip form, trip detail (sections, linked meals/chores)
        ├── Meals/                      ← Meal list, rows, add/edit sheet, My Meals library (saved meals)
        └── Settings/                   ← Members, invite code, notifications, data summary
```

---

## Getting Started

### 1. Open the project

```bash
open ~/Coding/HouseholdApp/HouseholdApp.xcodeproj
```

### 2. Firebase setup (already done for this repo)

The app is connected to the Firebase project **`jordan-code`** via `HouseholdApp/GoogleService-Info.plist`. To point at a different Firebase project:

1. Create a project at [console.firebase.google.com](https://console.firebase.google.com) and add an iOS app with bundle ID `com.householdapp.app`.
2. Download its `GoogleService-Info.plist` into `HouseholdApp/`.
3. Enable **Anonymous** and **Google** sign-in providers under Authentication.
4. Create a **Cloud Firestore** database and deploy the rules:

```bash
npm install -g firebase-tools   # once
firebase login                  # once
firebase deploy --only firestore:rules
```

### 3. Run on the Simulator

1. Select an iPhone simulator in Xcode's toolbar and press **Cmd+R**, or:

```bash
xcodebuild -project HouseholdApp.xcodeproj -scheme HouseholdApp -sdk iphonesimulator \
  -destination 'id=4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF' build
xcrun simctl install 4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF <path-to-built-.app>
xcrun simctl launch 4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF com.householdapp.app
```

The app signs in anonymously, auto-creates a household, and is immediately usable — no setup screen.

### 4. Run on a real device

1. Connect the iPhone via USB (unlocked).
2. In Xcode: **Signing & Capabilities** → select your Team.
3. Select the device and press **Cmd+R**.
4. On the phone, trust the developer under **Settings → General → VPN & Device Management**.

With a free personal team the install expires after **7 days** — `scripts/refresh-sideload.sh` rebuilds and reinstalls on all household phones (runs automatically via launchd on Sundays; phones must be unlocked and reachable).

---

## Household Sharing

Each person uses their own device and their own (anonymous or Google) Firebase account.

1. **Person A** installs the app — a household is auto-created for them.
2. Person A opens **Settings → Household Sharing** and shares the 6-character **invite code**.
3. **Person B** taps **Join a Different Household** in their Settings and enters the code.
4. Both phones now read and write the same household — chores, shopping, meals, and member names all sync in real time.

### How it works under the hood

- All data lives under a single Firestore document tree: `/households/{householdId}` with subcollections `chores`, `categories`, `completions`, `shoppingItems`, `meals`, `savedMeals`, `trips`, `packingItems`, `gardenPlants`, and `wishes`.
- The household doc holds `memberIds` (Firebase Auth UIDs). Security rules only allow reads/writes when `request.auth.uid` is in that array.
- Invite codes live at `/invites/{code} → householdId`. Only household members can create or rotate codes; joining adds your UID to `memberIds` (and may touch nothing else).
- Each store (`ChoreStore`, `ShoppingStore`, `MealStore`, `CategoryStore`) keeps a snapshot listener open, so remote edits appear immediately; Firestore's local cache keeps the app working offline.
- Signing in with Google links the anonymous account, preserving the same UID (and therefore household membership) across reinstalls.

---

## Data Model (Firestore)

All documents are Codable Swift structs in `HouseholdApp/Firebase/`.

### HouseholdDoc — `/households/{id}`

| Field | Type | Description |
|---|---|---|
| `name` | String? | Optional display name |
| `inviteCode` | String | 6-character join code (also indexed at `/invites/{code}`) |
| `memberIds` | [String] | Firebase Auth UIDs with access — enforced by security rules |
| `ownerId` | String | UID of the creator |
| `memberNames` | [String]? | Shared display names, synced to every device |

### ChoreDoc — `…/chores/{id}`

| Field | Type | Description |
|---|---|---|
| `title` / `notes` | String / String? | Description |
| `assignedToMembers` | [Int] | Member indices; empty = Everyone |
| `dueDateType` | Int16 | 0=Specific date, 1=Week, 2=Month, 3=None |
| `dueDate` | Date? | A date within the selected day/week/month |
| `repeatInterval` | Int16 | 0=None, 1=Daily, 2=Weekly, 3=Biweekly, 4=Monthly, 5=Yearly |
| `isCompleted` / `completedAt` | Bool / Date? | Completion state (auto-cleaned after 1 month) |
| `completedByMembers` | [Int] | Who completed it |
| `categoryId` | String? | Links to a CategoryDoc |

### ShoppingItemDoc — `…/shoppingItems/{id}`

| Field | Type | Description |
|---|---|---|
| `name` / `quantity` / `notes` | String / String? / String? | Item details |
| `store` / `itemType` | String? | Grouping keys (user-editable lists in Settings) |
| `assignedToMembers` | [Int] | Member indices; empty = Everyone |
| `isPurchased` / `purchasedAt` | Bool / Date? | Purchase state (auto-cleaned after 1 month) |
| `mealId` / `mealName` | String? | Set when the item was added from a meal's ingredient list — powers the badge that links back to the meal |

### MealDoc — `…/meals/{id}`

| Field | Type | Description |
|---|---|---|
| `name` | String? | Optional dish name (falls back to the meal type) |
| `day` | Date | Planned day (meals >1 month past are auto-cleaned) |
| `mealType` | String | breakfast / brunch / lunch / dinner / snack / dessert |
| `assignedToMembers` | [Int] | Who's cooking; empty = Everyone |
| `ingredients` | [MealIngredient] | Each has `name`, `have` (on hand?), `addedToList` |
| `isCompleted` / `completedAt` | Bool / Date? | Whether the meal was made |

### CategoryDoc / CompletionLogDoc

Categories: `name`, `colorHex`, `iconName`, `sortOrder`. Completion logs: `choreId`, `completedAt`, `completedByMemberIndex` — powers per-person history.

---

## Security Rules

`firestore.rules` is the source of truth; deploy with `firebase deploy --only firestore:rules`.

- Household reads/updates/deletes require your UID in `memberIds`.
- Household creation requires you to be the sole member and owner.
- Joining (self-add to `memberIds`) may touch **only** that field.
- Invite codes can only be created by the household owner (same-batch creation) or an existing member (rotation) — prevents invite forgery.
- Invites allow `get` by exact code only — `list` is denied, so codes can't be enumerated by querying the collection.
- Every subcollection (`chores`, `categories`, `completions`, `shoppingItems`, `meals`, `savedMeals`, `trips`, `packingItems`, `gardenPlants`, `wishes`) is member-only.

---

## Repeat Logic

HouseholdApp uses a **rolling repeat** model:

- When you mark a repeating chore complete, it is **not archived** — its due date advances by the interval and a `CompletionLog` records the completion.
- Non-repeating chores are archived in place (`isCompleted = true`) and shown in the **Completed** section until auto-cleanup removes them a week later.

---

## Regenerating the Xcode Project

If you add new Swift files, regenerate the `.xcodeproj`:

```bash
cd ~/Coding/HouseholdApp
xcodegen generate
git checkout -- HouseholdApp/HouseholdApp.entitlements   # xcodegen overwrites the entitlements file
```

The source of truth is `project.yml` — never edit `project.pbxproj` by hand.

---

## Known Limitations / Future Ideas

- **No cross-device push notifications** (e.g. "your wife added an item") — would require Cloud Functions on Firebase's paid Blaze plan. Local due-date reminders work today.
- **No widget** — a home screen widget showing today's chores/meals via `WidgetKit`.
- **No drag-to-reorder** — `sortOrder` fields are in place; a `List` with `.onMove` would enable it.
- **No dashboard/scoreboard** — `CompletionLog` tracks per-person history; a stats view could show streaks and completion counts.

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Backend | Firebase — Cloud Firestore (real-time sync + offline cache), Firebase Auth (anonymous + Google) |
| Notifications | Local only (`UNUserNotificationCenter`) |
| Settings storage | UserDefaults via `@AppStorage` (device-local prefs) |
| Minimum OS | iOS 17 |
| Language | Swift 5.9 |
| Project generation | xcodegen |

## Planning meals from a spreadsheet

Some people would rather plan a week (or a trip) in a spreadsheet than tap through a phone form. The Meals tab has a table icon that:

1. **Shares the template** (`MealPlanTemplate.xlsx`, also in this repo under `HouseholdApp/Resources/`). Open it in Excel, Google Sheets, or Numbers.
2. **Imports the filled-in file** — save as `.xlsx` (Google Sheets: *File › Download › Microsoft Excel*), pick it in the app.

**Sheets:** `Meals` (required — one row per meal), `Trips` and `Packing` (optional). Orange headers are required, blue are optional; hover a header for details, and the `Instructions` sheet has examples.

| Sheet | Required | Optional |
|---|---|---|
| Meals | Date, Meal (dropdown) | Meal Name, Cook, Ingredients (have), Ingredients to Buy, Trip Name, Recipe Link, Instructions, Notes |
| Trips | Trip Name, Start Date, End Date | Notes |
| Packing | Trip Name, Item | Section (dropdown) |

**What gets created:** each row → a meal; each "Ingredients to Buy" entry → a shopping item linked to the meal; a Trip Name that doesn't exist → a new trip (dated from the Trips sheet, or spanning its meals' dates); meals on a trip put all their ingredients on the packing list under Food; Packing rows → packing items.

**Error-proofing:** headers, sheet names, and the Instructions sheet are locked in the template; dropdowns and date validation guard the cells. On import, headers are matched case-insensitively with aliases, dates are accepted in most typed forms, blank rows are ignored, and every problem row is reported with its sheet and row number while the rest still import. Meals, items, and trips that already exist are skipped.

Regenerate the template after changing columns with `python3 scripts/make-meal-template.py` (needs `openpyxl`), and keep `MealPlanImporter.swift`'s aliases in sync.
