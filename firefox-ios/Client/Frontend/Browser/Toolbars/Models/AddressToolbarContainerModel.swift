// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import ToolbarKit
import Shared

class AddressToolbarContainerModel: Equatable {
    let navigationActions: [ToolbarElement]
    let pageActions: [ToolbarElement]
    let browserActions: [ToolbarElement]

    let borderPosition: AddressToolbarBorderPosition?
    let searchEngineImage: UIImage?
    let searchEngines: SearchEngines
    let url: URL?

    let windowUUID: UUID

    var addressToolbarState: AddressToolbarState {
        let locationViewState = LocationViewState(
            searchEngineImageViewA11yId: AccessibilityIdentifiers.Browser.AddressToolbar.lockIcon,
            searchEngineImageViewA11yLabel: .AddressToolbar.PrivacyAndSecuritySettingsA11yLabel,
            lockIconButtonA11yId: AccessibilityIdentifiers.Browser.AddressToolbar.searchEngine,
            lockIconButtonA11yLabel: .AddressToolbar.SearchEngineA11yLabel,
            urlTextFieldPlaceholder: .AddressToolbar.LocationPlaceholder,
            urlTextFieldA11yId: AccessibilityIdentifiers.Browser.AddressToolbar.searchTextField,
            urlTextFieldA11yLabel: .AddressToolbar.LocationA11yLabel,
            searchEngineImage: searchEngineImage,
            lockIconImageName: StandardImageIdentifiers.Medium.lock,
            url: url,
            searchTerm: searchTermFromURL(url, searchEngines: searchEngines),
            onTapLockIcon: {
                let action = ToolbarMiddlewareAction(buttonType: .trackingProtection,
                                                     gestureType: .tap,
                                                     windowUUID: self.windowUUID,
                                                     actionType: ToolbarMiddlewareActionType.didTapButton)
                store.dispatch(action)
            })
        return AddressToolbarState(
            locationViewState: locationViewState,
            navigationActions: navigationActions,
            pageActions: pageActions,
            browserActions: browserActions,
            borderPosition: borderPosition)
    }

    init(state: ToolbarState, profile: Profile, windowUUID: UUID) {
        self.borderPosition = state.addressToolbar.borderPosition
        self.navigationActions = AddressToolbarContainerModel.mapActions(state.addressToolbar.navigationActions,
                                                                         state: state,
                                                                         windowUUID: windowUUID)
        self.pageActions = AddressToolbarContainerModel.mapActions(state.addressToolbar.pageActions,
                                                                   state: state,
                                                                   windowUUID: windowUUID)
        self.browserActions = AddressToolbarContainerModel.mapActions(state.addressToolbar.browserActions,
                                                                      state: state,
                                                                      windowUUID: windowUUID)
        self.windowUUID = windowUUID
        self.searchEngineImage = profile.searchEngines.defaultEngine?.image
        self.searchEngines = profile.searchEngines
        self.url = state.addressToolbar.url
    }

    func searchTermFromURL(_ url: URL?, searchEngines: SearchEngines) -> String? {
        var searchURL: URL? = url

        if let url = searchURL, InternalURL.isValid(url: url) {
            searchURL = url
        }

        guard let query = searchEngines.queryForSearchURL(searchURL) else { return nil }
        return query
    }

    private static func mapActions(
        _ actions: [ToolbarActionState],
        state: ToolbarState,
        windowUUID: UUID
    ) -> [ToolbarElement] {
        return actions.map { action in
            let badgeImageName: String? = if state.isPrivateMode && action.canShowPrivateBrowsingBadge {
                action.badgeImageName
            } else {
                if state.isLoginActionRequired && action.canShowWarningBadge {
                    action.badgeImageName
                } else {
                    nil
                }
            }
            return ToolbarElement(
                iconName: action.iconName,
                badgeImageName: badgeImageName,
                numberOfTabs: action.numberOfTabs,
                isEnabled: action.isEnabled,
                a11yLabel: action.a11yLabel,
                a11yId: action.a11yId,
                onSelected: { button in
                    let action = ToolbarMiddlewareAction(buttonType: action.actionType,
                                                         buttonTapped: button,
                                                         gestureType: .tap,
                                                         windowUUID: windowUUID,
                                                         actionType: ToolbarMiddlewareActionType.didTapButton)
                    store.dispatch(action)
                }, onLongPress: action.canPerformLongPressAction ? {
                    let action = ToolbarMiddlewareAction(buttonType: action.actionType,
                                                         gestureType: .longPress,
                                                         windowUUID: windowUUID,
                                                         actionType: ToolbarMiddlewareActionType.didTapButton)
                    store.dispatch(action)
                } : nil
            )
        }
    }

    static func == (lhs: AddressToolbarContainerModel, rhs: AddressToolbarContainerModel) -> Bool {
        lhs.navigationActions == rhs.navigationActions &&
        lhs.pageActions == rhs.pageActions &&
        lhs.browserActions == rhs.browserActions &&
        lhs.borderPosition == rhs.borderPosition &&
        lhs.searchEngineImage == rhs.searchEngineImage &&
        lhs.url == rhs.url &&
        lhs.windowUUID == rhs.windowUUID
    }
}
