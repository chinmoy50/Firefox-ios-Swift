// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Public interface for contextual hint consumers
protocol ContextualHintEligibilityUtilityProtocol {
    func canPresent(_ hint: ContextualHintType) -> Bool
}

struct ContextualHintEligibilityUtility: ContextualHintEligibilityUtilityProtocol, ContextualHintPrefsKeysProvider {

    var profile: Profile

    init(with profile: Profile) {
        self.profile = profile
    }

    /// Determine if this hint is eligible to present, outside of Nimbus flag settings.
    func canPresent(_ hintType: ContextualHintType) -> Bool {
        guard isDeviceReady else { return false }

        var hintTypeShouldBePresented = false

        switch hintType {
        case .jumpBackIn:
            hintTypeShouldBePresented = canJumpBackInBePresented
        case .jumpBackInSyncedTab:
            hintTypeShouldBePresented = canPresentJumpBackInSyncedTab
        case .toolbarLocation:
            hintTypeShouldBePresented = SearchBarSettingsViewModel.isEnabled
        case .inactiveTabs:
            hintTypeShouldBePresented = true
        }

        return hintTypeShouldBePresented && !hasAlreadyBeenPresented(hintType)
    }

    // MARK: - Private helpers

    // Do not present contextual hint in landscape on iPhone
    private var isDeviceReady: Bool {
        !UIWindow.isLandscape || UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Determine if the CFR for Jump Back In is presentable.
    ///
    /// It's presentable on these conditions:
    /// - this CFR should not be presented on iPad
    /// - the Toolbar CFR has already been presented
    /// - the JumpBackInSyncedTab CFR has NOT been presented already
    /// - the JumpBackIn CFR has NOT been presented yet
    private var canJumpBackInBePresented: Bool {
        guard let hasPresentedToolbarCFR = profile.prefs.boolForKey(CFRPrefsKeys.toolbarOnboardingKey.rawValue),
              hasPresentedToolbarCFR,
              !hasHintBeenConfigured(.jumpBackInSyncedTab),
              !hasAlreadyBeenPresented(.jumpBackInSyncedTab)
        else { return false }

        return true
    }

    /// Determine if the CFR for SyncedTab in JumpBackIn is presentable.
    ///
    /// The context hint is presentable when certain conditions are met:
    /// - A synced tab appears in Jump Back In
    /// - The Toolbar CFR has been presented
    /// - This CFR hasn't already been presented
    /// - The Home Tab Banner isn't being displayed (not specified by Product, but the CFR might show when the anchor point isn't on screen)
    private var canPresentJumpBackInSyncedTab: Bool {
        guard let hasPresentedToolbarCFR = profile.prefs.boolForKey(CFRPrefsKeys.toolbarOnboardingKey.rawValue),
              hasPresentedToolbarCFR else { return false }

        return true
    }

    private func hasAlreadyBeenPresented(_ hintType: ContextualHintType) -> Bool {
        guard let contextualHintData = profile.prefs.boolForKey(prefsKey(for: hintType)) else { return false }

        return contextualHintData
    }

    /// In cases where hints need to be made aware of each other, this will inform of configured ones.
    ///
    /// Hints are configured when the anchor point is visible on screen. Sometimes, multiple hints can become
    /// configured and be eligible to present together. One hint can affect whether or not another should be
    /// presented, but currently hints are unaware of each other.
    ///
    /// With this method, if `hintA` needs to be aware of `hintB`, `hintA` can query for whether `hintB`
    /// has been configured. Then, `hintA` can react accordingly.
    ///
    /// This is a workaround for hints becoming aware of each other until we have a proper CFR system in place.
    private func hasHintBeenConfigured(_ hintType: ContextualHintType) -> Bool {

        var hintConfigured = false

        switch hintType {
        case .jumpBackIn:
            guard let jumpBackInConfigured = profile.prefs.boolForKey(CFRPrefsKeys.jumpBackInConfiguredKey.rawValue) else { return false }
            hintConfigured = jumpBackInConfigured
        case .jumpBackInSyncedTab:
            guard let syncedTabConfigured = profile.prefs.boolForKey(CFRPrefsKeys.jumpBackInSyncedTabConfiguredKey.rawValue) else { return false }
            hintConfigured = syncedTabConfigured
        default: break
        }

        return hintConfigured
    }

}
