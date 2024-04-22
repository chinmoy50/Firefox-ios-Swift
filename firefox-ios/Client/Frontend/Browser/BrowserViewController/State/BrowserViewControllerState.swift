// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux
import Shared

struct BrowserViewControllerState: ScreenState, Equatable {
    let windowUUID: WindowUUID
    var searchScreenState: SearchScreenState
    var showDataClearanceFlow: Bool
    var fakespotState: FakespotState
    var toast: ToastType?
    var showOverlay: Bool
    var reloadWebView: Bool
    var browserViewType: BrowserViewType

    init(appState: AppState, uuid: WindowUUID) {
        guard let bvcState = store.state.screenState(
            BrowserViewControllerState.self,
            for: .browserViewController,
            window: uuid)
        else {
            self.init(windowUUID: uuid)
            return
        }

        self.init(searchScreenState: bvcState.searchScreenState,
                  showDataClearanceFlow: bvcState.showDataClearanceFlow,
                  fakespotState: bvcState.fakespotState,
                  toast: bvcState.toast,
                  showOverlay: bvcState.showOverlay,
                  windowUUID: bvcState.windowUUID,
                  reloadWebView: bvcState.reloadWebView,
                  browserViewType: bvcState.browserViewType)
    }

    init(windowUUID: WindowUUID) {
        self.init(
            searchScreenState: SearchScreenState(),
            showDataClearanceFlow: false,
            fakespotState: FakespotState(windowUUID: windowUUID),
            toast: nil,
            showOverlay: false,
            windowUUID: windowUUID,
            browserViewType: .normalHomepage)
    }

    init(
        searchScreenState: SearchScreenState,
        showDataClearanceFlow: Bool,
        fakespotState: FakespotState,
        toast: ToastType? = nil,
        showOverlay: Bool = false,
        windowUUID: WindowUUID,
        reloadWebView: Bool = false,
        browserViewType: BrowserViewType
    ) {
        self.searchScreenState = searchScreenState
        self.showDataClearanceFlow = showDataClearanceFlow
        self.fakespotState = fakespotState
        self.toast = toast
        self.windowUUID = windowUUID
        self.showOverlay = showOverlay
        self.reloadWebView = reloadWebView
        self.browserViewType = browserViewType
    }

    static let reducer: Reducer<Self> = { state, action in
        // Only process actions for the current window
        guard action.windowUUID == .unavailable || action.windowUUID == state.windowUUID else { return state }

        if let action as? FakespotAction {
            return BrowserViewControllerState.reduceStateForFakeSpotAction(action: action, state: state)
        } else if let action as? PrivateModeAction {
            return BrowserViewControllerState.reduceStateForPrivateModeAction(action: action, state: state)
        }

        // TODO: Move other actions
        switch action {
        case GeneralBrowserAction.showToast(let context):
            let toastType = context.toastType
            return BrowserViewControllerState(
                searchScreenState: state.searchScreenState,
                showDataClearanceFlow: state.showDataClearanceFlow,
                fakespotState: FakespotState.reducer(state.fakespotState, action),
                toast: toastType,
                windowUUID: state.windowUUID,
                browserViewType: state.browserViewType)
        case GeneralBrowserAction.showOverlay(let context):
            let showOverlay = context.showOverlay
            return BrowserViewControllerState(
                searchScreenState: state.searchScreenState,
                showDataClearanceFlow: state.showDataClearanceFlow,
                fakespotState: FakespotState.reducer(state.fakespotState, action),
                showOverlay: showOverlay,
                windowUUID: state.windowUUID,
                browserViewType: state.browserViewType)
        case GeneralBrowserAction.updateSelectedTab(let context):
            return BrowserViewControllerState.resolveStateForUpdateSelectedTab(context, state: state)
        default:
            return BrowserViewControllerState(
                searchScreenState: state.searchScreenState,
                showDataClearanceFlow: state.showDataClearanceFlow,
                fakespotState: FakespotState.reducer(state.fakespotState, action),
                showOverlay: state.showOverlay,
                windowUUID: state.windowUUID,
                reloadWebView: false,
                browserViewType: state.browserViewType)
        }
    }

    static func reduceStateForFakeSpotAction(action: FakespotAction,
                                             state: BrowserViewControllerState) -> BrowserViewControllerState {
        return BrowserViewControllerState(
            searchScreenState: state.searchScreenState,
            showDataClearanceFlow: state.showDataClearanceFlow,
            fakespotState: FakespotState.reducer(state.fakespotState, action),
            windowUUID: state.windowUUID,
            browserViewType: state.browserViewType)
    }

    static func reduceStateForPrivateModeAction(action: PrivateModeAction,
                                                state: BrowserViewControllerState) -> BrowserViewControllerState {
        switch action.actionType {
        case PrivateModeActionType.privateModeUpdated:
            let privacyState = action.isPrivate ?? false
            var browserViewType = state.browserViewType
            if browserViewType != .webview {
                browserViewType = privacyState ? .privateHomepage : .normalHomepage
            }
            return BrowserViewControllerState(
                searchScreenState: SearchScreenState(inPrivateMode: privacyState),
                showDataClearanceFlow: privacyState,
                fakespotState: FakespotState.reducer(state.fakespotState, action),
                windowUUID: state.windowUUID,
                reloadWebView: true,
                browserViewType: browserViewType)
        default:
            return state
        }
    }

    static func resolveStateForUpdateSelectedTab(_ context: GeneralBrowserContext,
                                                 state: BrowserViewControllerState) -> BrowserViewControllerState {
        let isAboutHomeURL = InternalURL(context.selectedTabURL)?.isAboutHomeURL ?? false
        var browserViewType = BrowserViewType.normalHomepage

        if isAboutHomeURL {
            browserViewType = context.isPrivateBrowsing ? .privateHomepage : .normalHomepage
        } else {
            browserViewType = .webview
        }

        return BrowserViewControllerState(
            searchScreenState: state.searchScreenState,
            showDataClearanceFlow: state.showDataClearanceFlow,
            fakespotState: state.fakespotState,
            showOverlay: state.showOverlay,
            windowUUID: state.windowUUID,
            reloadWebView: true,
            browserViewType: browserViewType)
    }
}
