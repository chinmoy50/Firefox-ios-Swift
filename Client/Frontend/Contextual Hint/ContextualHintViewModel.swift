// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
import Shared
import UIKit

enum CFRTelemetryEvent {
    case closeButton
    case tapToDismiss
    case performAction
}

enum ContextualHintViewType: String {
    typealias CFRStrings = String.ContextualHints
    
    case jumpBackIn = "JumpBackIn"
    case inactiveTabs = "InactiveTabs"
    case toolbarLocation = "ToolbarLocation"
    
    func descriptionText() -> String {
        switch self {
        case .inactiveTabs: return CFRStrings.TabsTray.InactiveTabs.Body
        case .jumpBackIn: return CFRStrings.FirefoxHomepage.JumpBackIn.PersonalizedHome
            
        case .toolbarLocation:
            switch SearchBarSettingsViewModel.getDefaultSearchPosition() {
            case .top: return CFRStrings.Toolbar.SearchBarPlacementForNewUsers
            case .bottom: return CFRStrings.Toolbar.SearchBarPlacementForExistingUsers
            }
        }
    }
    
    func buttonActionText() -> String {
        switch self {
        case .inactiveTabs: return CFRStrings.TabsTray.InactiveTabs.Action
        case .toolbarLocation: return CFRStrings.Toolbar.SearchBarPlacementButtonText
        default: return ""
        }
    }
    
    func isActionType() -> Bool {
        switch self {
        case .inactiveTabs,
                .toolbarLocation:
            return true
            
        default: return false
        }
    }
}

class ContextualHintViewModel {

    // MARK: - Properties
    var hintType: ContextualHintViewType
    var timer: Timer?
    var presentFromTimer: (() -> Void)? = nil
    private var profile: Profile
    private var hasSentDismissEvent = false
    
    var hasAlreadyBeenPresented: Bool {
        // Prevent JumpBackIn CFR from being presented if the onboarding
        // CFR has not yet been presented.
//        if hintType == .jumpBackIn,
//           profile.prefs.boolForKey(PrefsKeys.ContextualHints.ToolbarOnboardingKey) {
//            return false
//        }
//
        guard let contextualHintData = profile.prefs.boolForKey(prefsKey) else {
            return false
        }
        
        return contextualHintData
    }
    
    // Do not present contextual hint in landscape on iPhone
    private var isDeviceHintReady: Bool {
        !UIWindow.isLandscape || UIDevice.current.userInterfaceIdiom == .pad
    }
    
    private var prefsKey: String {
        switch hintType {
        case .inactiveTabs: return PrefsKeys.ContextualHints.InactiveTabsKey
        case .jumpBackIn: return PrefsKeys.ContextualHints.JumpBackinKey
        case .toolbarLocation: return PrefsKeys.ContextualHints.ToolbarOnboardingKey
        }
    }
    
    // MARK: - Initializers
    init(forHintType hintType: ContextualHintViewType, with profile: Profile) {
        self.hintType = hintType
        self.profile = profile
    }
    
    // MARK: - Interface
    func shouldPresentContextualHint() -> Bool {
        guard isDeviceHintReady else { return false }
        return !hasAlreadyBeenPresented
    }
    
    func markContextualHintPresented() {
        profile.prefs.setBool(true, forKey: prefsKey)
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(timeInterval: 1.25,
                                     target: self,
                                     selector: #selector(presentHint),
                                     userInfo: nil,
                                     repeats: false)
    }
    
    func stopTimer() {
        timer?.invalidate()
    }
    
    // MARK: - Telemetry
    func sendTelemetryEvent(for eventType: CFRTelemetryEvent) {
        let extra = [TelemetryWrapper.EventExtraKey.cfrType.rawValue: hintType.rawValue]
        
        switch eventType {
        case .closeButton:
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .contextualHint,
                                         value: .dismissCFRFromButton,
                                         extras: extra)
            hasSentDismissEvent = true
        case .tapToDismiss:
            if hasSentDismissEvent { return }
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .contextualHint,
                                         value: .dismissCFRFromOutsideTap,
                                         extras: extra)
        case .performAction:
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .contextualHint,
                                         value: .pressCFRActionButton,
                                         extras: extra)
        }
    }
    
    // MARK: - Present
    @objc private func presentHint() {
        timer?.invalidate()
        timer = nil
        presentFromTimer?()
        presentFromTimer = nil
    }
}

