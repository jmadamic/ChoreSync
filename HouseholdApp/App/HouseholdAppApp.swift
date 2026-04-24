// HouseholdAppApp.swift
import SwiftUI
import FirebaseCore

@main
struct HouseholdAppApp: App {

    @StateObject private var appSettings       = AppSettings()
    @StateObject private var auth              = AuthController()
    @StateObject private var householdCtrl     = HouseholdController()
    @StateObject private var choreStore        = ChoreStore()
    @StateObject private var categoryStore     = CategoryStore()
    @StateObject private var shoppingStore     = ShoppingStore()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !auth.isSignedIn {
                    // Anonymous sign-in is in-flight — show a brief spinner.
                    ProgressView()
                } else if householdCtrl.household == nil {
                    // Still setting up (auto-creating household or loading from Firestore).
                    // Show a spinner; once the household doc arrives we switch to RootView.
                    ProgressView("Setting up…")
                        .task {
                            await householdCtrl.autoCreateIfNeeded()
                        }
                } else {
                    RootView()
                        .environmentObject(appSettings)
                        .environmentObject(auth)
                        .environmentObject(householdCtrl)
                        .environmentObject(choreStore)
                        .environmentObject(categoryStore)
                        .environmentObject(shoppingStore)
                        .onAppear {
                            appSettings.migrateFromOldFormat()
                            if let hid = householdCtrl.household?.id {
                                choreStore.startListening(householdId: hid)
                                categoryStore.startListening(householdId: hid)
                                categoryStore.seedDefaults(householdId: hid)
                                shoppingStore.startListening(householdId: hid)
                            }
                        }
                        .task {
                            await NotificationManager.shared.requestPermissionIfNeeded()
                        }
                        .onChange(of: householdCtrl.household?.id) { _, newId in
                            if let hid = newId {
                                choreStore.startListening(householdId: hid)
                                categoryStore.startListening(householdId: hid)
                                categoryStore.seedDefaults(householdId: hid)
                                shoppingStore.startListening(householdId: hid)
                            }
                        }
                }
            }
            .preferredColorScheme(appSettings.appearance.colorScheme)
        }
    }
}
