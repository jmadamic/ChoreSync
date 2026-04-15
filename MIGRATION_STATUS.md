# Firestore Migration Status

This branch (`firestore-migration`) replaces CloudKit + Core Data with
Firebase Auth + Firestore, so the app can be used without paying for an
Apple Developer account for CloudKit.

## Phase 1 — Foundation (done)

All Firebase scaffolding is in place:

```
HouseholdApp/Firebase/
├── ChoreDoc.swift           Codable model — replaces Core Data Chore
├── CategoryDoc.swift        Codable model — replaces Category
├── CompletionLogDoc.swift   Codable model — replaces CompletionLog
├── ShoppingItemDoc.swift    Codable model — replaces ShoppingItem
├── HouseholdDoc.swift       New top-level "group" doc
├── AuthController.swift     Google Sign-In + Firebase Auth
├── HouseholdController.swift Create / join / leave household
├── ChoreStore.swift         Observable Firestore listener
├── CategoryStore.swift      Observable Firestore listener
└── ShoppingStore.swift      Observable Firestore listener

HouseholdApp/Views/Auth/
├── SignInView.swift             Google Sign-In button
└── HouseholdSetupView.swift     Create household / join via code

firestore.rules                  Security rules (paste into Firebase console)
```

`project.yml` now declares Firebase and GoogleSignIn SPM packages.

## User action required before Phase 2

Before the app will build/run, you need to:

### 1. Create Firebase project (one-time)
- [console.firebase.google.com](https://console.firebase.google.com) → **Add project** → name it anything
- Turn off Google Analytics
- Click iOS icon → bundle ID `com.householdapp.app` → nickname HouseholdApp
- Download **`GoogleService-Info.plist`**
- Move it to: `HouseholdApp/HouseholdApp/GoogleService-Info.plist`

### 2. Enable Google Sign-In
- Firebase console → **Build → Authentication** → Get Started
- Click **Google** provider → Enable → pick a support email → Save

### 3. Create Firestore
- Firebase console → **Build → Firestore Database** → Create database
- Start in **production mode** (we'll paste custom rules next)
- Pick a region close to you (e.g. `nam5` for North America)

### 4. Paste security rules
- Firebase console → **Firestore Database → Rules**
- Replace the default rules with the contents of `firestore.rules`
- Click **Publish**

### 5. Add Google Sign-In URL scheme
- Open `GoogleService-Info.plist` — copy the `REVERSED_CLIENT_ID` value
- Open `HouseholdApp/HouseholdApp/Info.plist`
- Add a URL scheme to `CFBundleURLTypes` with that value as a URL scheme

### 6. Regenerate Xcode project + fetch SPM packages
```bash
cd ~/Coding/HouseholdApp
xcodegen generate
# Restore entitlements — xcodegen wipes them:
git checkout -- HouseholdApp/HouseholdApp.entitlements
open HouseholdApp.xcodeproj
# Xcode will auto-resolve Firebase + GoogleSignIn SPM packages (~1 min)
```

## Phase 2 — View migration (not done yet)

All existing views still reference Core Data (`@FetchRequest`, `Chore` class,
etc.) and **will not compile** against Firestore stores. Phase 2 rewrites:

- [ ] `HouseholdAppApp.swift` — initialize Firebase, gate on auth + household
- [ ] `RootView.swift` — inject stores as `@EnvironmentObject`
- [ ] `ChoreListView.swift` + `ChoreRowView.swift` — use `ChoreStore`
- [ ] `ChoreFormView.swift` — save via `ChoreStore.save()`
- [ ] `CategoryFormView.swift` — save via `CategoryStore`
- [ ] `CategoryListView.swift` — use `CategoryStore`
- [ ] `ShoppingListView.swift` + `ShoppingRowView.swift` — use `ShoppingStore`
- [ ] `ShoppingFormView.swift` — save via `ShoppingStore`
- [ ] `SettingsView.swift` — replace CloudKit share UI with invite code UI
- [ ] Seed default categories for new households
- [ ] Delete `Persistence/`, `HouseholdApp.xcdatamodeld/`, `ShareController.swift`,
      `CoreDataHelpers.swift`
- [ ] Strip iCloud keys from `HouseholdApp.entitlements`

## Architecture reference

```
/households/{householdId}               ← HouseholdDoc
    /chores/{choreId}                   ← ChoreDoc
    /categories/{categoryId}            ← CategoryDoc
    /completions/{logId}                ← CompletionLogDoc
    /shoppingItems/{itemId}             ← ShoppingItemDoc

/invites/{6-char-code}                  ← maps code → householdId
```

Settings (person names, store list, item type list, icon mappings) stay local
in `@AppStorage` per device — unchanged by the migration.
