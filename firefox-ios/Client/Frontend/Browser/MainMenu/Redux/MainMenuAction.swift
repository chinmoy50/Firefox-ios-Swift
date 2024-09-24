// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import MenuKit
import Redux

final class MainMenuAction: Action {
    var navigationDestination: MenuNavigationDestination?
    var currentTabInfo: MainMenuTabInfo?

    init(
        windowUUID: WindowUUID,
        actionType: any ActionType,
        navigationDestination: MenuNavigationDestination? = nil,
        currentTabInfo: MainMenuTabInfo? = nil
    ) {
        self.navigationDestination = navigationDestination
        self.currentTabInfo = currentTabInfo
        super.init(windowUUID: windowUUID, actionType: actionType)
    }
}

enum MainMenuActionType: ActionType {
    case closeMenu
    case mainMenuDidAppear
    case navigate
    case toggleUserAgent
    case updateCurrentTabInfo
    case viewDidLoad
}

enum MainMenuMiddlewareActionType: ActionType {
    case requestTabInfo
}

enum MainMenuDetailsActionType: ActionType {
    case dismissView
    case updateSubmenuType(MainMenuDetailsViewType)
    case viewDidLoad
    case viewDidDisappear
}
