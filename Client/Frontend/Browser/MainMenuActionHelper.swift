// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import Foundation
import Shared
import Storage
import UIKit
import SwiftUI
import Common

protocol ToolBarActionMenuDelegate: AnyObject {
    func updateToolbarState()
    func addBookmark(url: String, title: String?)

    @discardableResult
    func openURLInNewTab(_ url: URL?, isPrivate: Bool) -> Tab
    func openNewTabFromMenu(focusLocationField: Bool, isPrivate: Bool)

    func showLibrary(panel: LibraryPanelType)
    func showViewController(viewController: UIViewController)
    func showToast(message: String, toastAction: MenuButtonToastAction, url: String?)
    func showMenuPresenter(url: URL, tab: Tab, view: UIView)
    func showFindInPage()
    func showCustomizeHomePage()
    func showZoomPage(tab: Tab)
    func showCreditCardSettings()
    func showSignInView(fxaParameters: FxASignInViewParameters)
}

enum MenuButtonToastAction {
    case share
    case addToReadingList
    case removeFromReadingList
    case bookmarkPage
    case removeBookmark
    case copyUrl
    case pinPage
    case removePinPage
}

/// MainMenuActionHelper handles the main menu (hamburger menu) in the toolbar.
/// There is three different types of main menu:
///     - The home page menu, determined with isHomePage variable
///     - The file URL menu, shown when the user is on a url of type `file://`
///     - The site menu, determined by the absence of isHomePage and isFileURL
class MainMenuActionHelper: PhotonActionSheetProtocol,
                            FeatureFlaggable,
                            CanRemoveQuickActionBookmark,
                            AppVersionUpdateCheckerProtocol {
    typealias SendToDeviceDelegate = InstructionsViewDelegate & DevicePickerViewControllerDelegate

    private let isHomePage: Bool
    private let buttonView: UIButton
    private let toastContainer: UIView
    private let selectedTab: Tab?
    private let tabUrl: URL?
    private let isFileURL: Bool

    let themeManager: ThemeManager
    var bookmarksHandler: BookmarksHandler
    let profile: Profile
    let tabManager: TabManager

    weak var delegate: ToolBarActionMenuDelegate?
    weak var sendToDeviceDelegate: SendToDeviceDelegate?
    weak var navigationHandler: BrowserNavigationHandler?

    /// MainMenuActionHelper init
    /// - Parameters:
    ///   - profile: the user's profile
    ///   - tabManager: the tab manager
    ///   - buttonView: the view from which the menu will be shown
    ///   - toastContainer: the view hosting a toast alert
    ///   - showFXASyncAction: the closure that will be executed for the sync action in the library section
    init(profile: Profile,
         tabManager: TabManager,
         buttonView: UIButton,
         toastContainer: UIView,
         themeManager: ThemeManager = AppContainer.shared.resolve()
    ) {
        self.profile = profile
        self.bookmarksHandler = profile.places
        self.tabManager = tabManager
        self.buttonView = buttonView
        self.toastContainer = toastContainer

        self.selectedTab = tabManager.selectedTab
        self.tabUrl = selectedTab?.url
        self.isFileURL = tabUrl?.isFileURL ?? false
        self.isHomePage = selectedTab?.isFxHomeTab ?? false
        self.themeManager = themeManager
    }

    func getToolbarActions(navigationController: UINavigationController?,
                           completion: @escaping ([[PhotonRowActions]]) -> Void) {
        var actions: [[PhotonRowActions]] = []
        let firstMiscSection = getFirstMiscSection(navigationController)

        if isHomePage {
            actions.append(contentsOf: [
                getLibrarySection(),
                firstMiscSection,
                getLastSection()
            ])

            completion(actions)
        } else {
            // Actions on site page need specific data to be loaded
            updateData(dataLoadingCompletion: {
                actions.append(contentsOf: [
                    self.getNewTabSection(),
                    self.getLibrarySection(),
                    firstMiscSection,
                    self.getSecondMiscSection(),
                    self.getLastSection()
                ])

                DispatchQueue.main.async {
                    completion(actions)
                }
            })
        }
    }

    // MARK: - Update data

    private let dataQueue = DispatchQueue(label: "com.moz.mainMenuAction.queue")
    private var isInReadingList = false
    private var isBookmarked = false
    private var isPinned = false

    /// Update data to show the proper menus related to the page
    /// - Parameter dataLoadingCompletion: Complete when the loading of data from the profile is done
    private func updateData(dataLoadingCompletion: (() -> Void)? = nil) {
        var url: String?

        if let tabUrl = tabUrl, tabUrl.isReaderModeURL, let tabUrlDecoded = tabUrl.decodeReaderModeURL {
            url = tabUrlDecoded.absoluteString
        } else {
            url = tabUrl?.absoluteString
        }

        guard let url = url else {
            dataLoadingCompletion?()
            return
        }

        let group = DispatchGroup()
        getIsBookmarked(url: url, group: group)
        getIsPinned(url: url, group: group)
        getIsInReadingList(url: url, group: group)

        let dataQueue = DispatchQueue.global()
        group.notify(queue: dataQueue) {
            dataLoadingCompletion?()
        }
    }

    private func getIsInReadingList(url: String, group: DispatchGroup) {
        group.enter()
        profile.readingList.getRecordWithURL(url).uponQueue(dataQueue) { result in
            self.isInReadingList = result.successValue != nil
            group.leave()
        }
    }

    private func getIsBookmarked(url: String, group: DispatchGroup) {
        group.enter()
        profile.places.isBookmarked(url: url).uponQueue(dataQueue) { result in
            self.isBookmarked = result.successValue ?? false
            group.leave()
        }
    }

    private func getIsPinned(url: String, group: DispatchGroup) {
        group.enter()
        profile.pinnedSites.isPinnedTopSite(url).uponQueue(dataQueue) { result in
            self.isPinned = result.successValue ?? false
            group.leave()
        }
    }

    // MARK: - Sections

    private func getNewTabSection() -> [PhotonRowActions] {
        var section = [PhotonRowActions]()
        append(to: &section, action: getNewTabAction())

        return section
    }

    private func getLibrarySection() -> [PhotonRowActions] {
        var section = [PhotonRowActions]()

        if !isFileURL {
            let bookmarkSection = getBookmarkSection()
            append(to: &section, action: bookmarkSection)

            let historySection = getHistoryLibraryAction()
            append(to: &section, action: historySection)

            let downloadSection = getDownloadsLibraryAction()
            append(to: &section, action: downloadSection)

            let readingListSection = getReadingListSection()
            append(to: &section, action: readingListSection)
        }

        let syncAction = syncMenuButton()
        append(to: &section, action: syncAction)

        return section
    }

    private func getFirstMiscSection(_ navigationController: UINavigationController?) -> [PhotonRowActions] {
        var section = [PhotonRowActions]()

        if !isHomePage && !isFileURL {
            if featureFlags.isFeatureEnabled(.zoomFeature, checking: .buildOnly) {
                let zoomAction = getZoomAction()
                append(to: &section, action: zoomAction)
            }

            let findInPageAction = getFindInPageAction()
            append(to: &section, action: findInPageAction)

            let desktopSiteAction = getRequestDesktopSiteAction()
            append(to: &section, action: desktopSiteAction)
        }

        let nightModeAction = getNightModeAction()
        append(to: &section, action: nightModeAction)

        let passwordsAction = getPasswordAction(navigationController: navigationController)
        append(to: &section, action: passwordsAction)

        if !isHomePage && !isFileURL {
            let reportSiteIssueAction = getReportSiteIssueAction()
            append(to: &section, action: reportSiteIssueAction)
        }

        return section
    }

    private func getSecondMiscSection() -> [PhotonRowActions] {
        var section = [PhotonRowActions]()

        if isFileURL {
            let shareFileAction = getShareFileAction()
            append(to: &section, action: shareFileAction)
        } else {
            let shortAction = getShortcutAction()
            append(to: &section, action: shortAction)

            // Feature flag for share sheet changes where we moved send to device and copy
            // away from hamburger menu to the actual system share sheet. When share sheet
            // changes flag is on we do not append items to the hamburger menu
            if !featureFlags.isFeatureEnabled(.shareSheetChanges, checking: .buildOnly) {
                let copyAction = getCopyAction()
                append(to: &section, action: copyAction)

                let sendToDeviceAction = getSendToDevice()
                append(to: &section, action: sendToDeviceAction)
            }

            // Feature flag for toolbar share action changes where if the toolbar is showing
            // share action button then we do not show the share button in hamburger menu
            if !featureFlags.isFeatureEnabled(.shareToolbarChanges, checking: .buildOnly) {
                let shareAction = getShareAction()
                append(to: &section, action: shareAction)
            }
        }

        return section
    }

    private func getLastSection() -> [PhotonRowActions] {
        var section = [PhotonRowActions]()

        if isHomePage {
            let whatsNewAction = getWhatsNewAction()
            append(to: &section, action: whatsNewAction)

            let helpAction = getHelpAction()
            section.append(helpAction)

            let customizeHomePageAction = getCustomizeHomePageAction()
            append(to: &section, action: customizeHomePageAction)
        }

        let settingsAction = getSettingsAction()
        section.append(settingsAction)

        return section
    }

    // MARK: - Actions

    private func getNewTabAction() -> PhotonRowActions? {
        guard let tab = selectedTab else { return nil }
        return SingleActionViewModel(title: .AppMenu.NewTab,
                                     iconString: StandardImageIdentifiers.Large.plus) { _ in
            let shouldFocusLocationField = NewTabAccessors.getNewTabPage(self.profile.prefs) != .homePage
            self.delegate?.openNewTabFromMenu(focusLocationField: shouldFocusLocationField, isPrivate: tab.isPrivate)
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .createNewTab)
        }.items
    }

    private func getHistoryLibraryAction() -> PhotonRowActions {
        return SingleActionViewModel(title: .AppMenu.AppMenuHistory,
                                     iconString: StandardImageIdentifiers.Large.history) { _ in
            self.delegate?.showLibrary(panel: .history)
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .viewHistoryPanel)
        }.items
    }

    private func getDownloadsLibraryAction() -> PhotonRowActions {
        return SingleActionViewModel(title: .AppMenu.AppMenuDownloads,
                                     iconString: StandardImageIdentifiers.Large.download) { _ in
            self.delegate?.showLibrary(panel: .downloads)
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .viewDownloadsPanel)
        }.items
    }

    // MARK: Zoom

    private func getZoomAction() -> PhotonRowActions? {
        guard let tab = selectedTab else { return nil }
        let zoomLevel = NumberFormatter.localizedString(from: NSNumber(value: tab.pageZoom), number: .percent)
        let title = String(format: .AppMenu.ZoomPageTitle, zoomLevel)
        let zoomAction = SingleActionViewModel(title: title,
                                               iconString: ImageIdentifiers.zoomIn) { _ in
            self.delegate?.showZoomPage(tab: tab)
        }.items
        return zoomAction
    }

    private func getFindInPageAction() -> PhotonRowActions {
        return SingleActionViewModel(title: .AppMenu.AppMenuFindInPageTitleString,
                                     iconString: ImageIdentifiers.findInPage) { _ in
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .findInPage)
            self.delegate?.showFindInPage()
        }.items
    }

    private func getRequestDesktopSiteAction() -> PhotonRowActions? {
        guard let tab = selectedTab else { return nil }

        let defaultUAisDesktop = UserAgent.isDesktop(ua: UserAgent.getUserAgent())
        let toggleActionTitle: String
        let toggleActionIcon: String
        let siteTypeTelemetryObject: TelemetryWrapper.EventObject
        if defaultUAisDesktop {
            toggleActionTitle = tab.changedUserAgent ? .AppMenu.AppMenuViewDesktopSiteTitleString : .AppMenu.AppMenuViewMobileSiteTitleString
            toggleActionIcon = tab.changedUserAgent ? StandardImageIdentifiers.Large.deviceDesktop : StandardImageIdentifiers.Large.deviceMobile
            siteTypeTelemetryObject = .requestDesktopSite
        } else {
            toggleActionTitle = tab.changedUserAgent ? .AppMenu.AppMenuViewMobileSiteTitleString : .AppMenu.AppMenuViewDesktopSiteTitleString
            toggleActionIcon = tab.changedUserAgent ? StandardImageIdentifiers.Large.deviceMobile : StandardImageIdentifiers.Large.deviceDesktop
            siteTypeTelemetryObject = .requestMobileSite
        }

        return SingleActionViewModel(title: toggleActionTitle,
                                     iconString: toggleActionIcon) { _ in
            if let url = tab.url {
                tab.toggleChangeUserAgent()
                Tab.ChangeUserAgent.updateDomainList(forUrl: url, isChangedUA: tab.changedUserAgent, isPrivate: tab.isPrivate)
                TelemetryWrapper.recordEvent(category: .action, method: .tap, object: siteTypeTelemetryObject)
            }
        }.items
    }

    private func getCopyAction() -> PhotonRowActions? {
        return SingleActionViewModel(title: .AppMenu.AppMenuCopyLinkTitleString,
                                     iconString: StandardImageIdentifiers.Large.link) { _ in
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .copyAddress)
            if let url = self.selectedTab?.canonicalURL?.displayURL {
                UIPasteboard.general.url = url
                self.delegate?.showToast(message: .AppMenu.AppMenuCopyURLConfirmMessage, toastAction: .copyUrl, url: nil)
            }
        }.items
    }

    private func getSendToDevice() -> PhotonRowActions {
        return SingleActionViewModel(title: .AppMenu.TouchActions.SendLinkToDeviceTitle,
                                     iconString: StandardImageIdentifiers.Large.deviceDesktopSend) { _ in
            guard let delegate = self.sendToDeviceDelegate,
                  let selectedTab = self.selectedTab,
                  let url = selectedTab.canonicalURL?.displayURL
            else { return }

            let themeColors = self.themeManager.currentTheme.colors
            let colors = SendToDeviceHelper.Colors(defaultBackground: themeColors.layer1,
                                                   textColor: themeColors.textPrimary,
                                                   iconColor: themeColors.iconPrimary)

            let shareItem = ShareItem(url: url.absoluteString,
                                      title: selectedTab.title)
            let helper = SendToDeviceHelper(shareItem: shareItem,
                                            profile: self.profile,
                                            colors: colors,
                                            delegate: delegate)

            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .sendToDevice)
            self.delegate?.showViewController(viewController: helper.initialViewController())
        }.items
    }

    private func getReportSiteIssueAction() -> PhotonRowActions? {
        guard featureFlags.isFeatureEnabled(.reportSiteIssue, checking: .buildOnly) else { return nil }

        return SingleActionViewModel(title: .AppMenu.AppMenuReportSiteIssueTitleString,
                                     iconString: StandardImageIdentifiers.Large.lightbulb) { _ in
            guard let tabURL = self.selectedTab?.url?.absoluteString else { return }
            self.delegate?.openURLInNewTab(SupportUtils.URLForReportSiteIssue(tabURL), isPrivate: false)
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .reportSiteIssue)
        }.items
    }

    private func getHelpAction() -> PhotonRowActions {
        return SingleActionViewModel(title: .AppMenu.Help,
                                     iconString: StandardImageIdentifiers.Large.helpCircle) { _ in
            if let url = URL(string: "https://support.mozilla.org/products/ios") {
                self.delegate?.openURLInNewTab(url, isPrivate: false)
            }
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .help)
        }.items
    }

    private func getCustomizeHomePageAction() -> PhotonRowActions? {
        return SingleActionViewModel(title: .AppMenu.CustomizeHomePage,
                                     iconString: StandardImageIdentifiers.Large.edit) { _ in
            self.delegate?.showCustomizeHomePage()
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .customizeHomePage)
        }.items
    }

    private func getSettingsAction() -> PhotonRowActions {
        let openSettings = SingleActionViewModel(title: .AppMenu.AppMenuSettingsTitleString,
                                                 iconString: ImageIdentifiers.settings) { _ in
            TelemetryWrapper.recordEvent(category: .action, method: .open, object: .settings)

            // Wait to show settings in async dispatch since hamburger menu is still showing at that time
            DispatchQueue.main.async {
                self.navigationHandler?.show(settings: .general)
            }
        }.items
        return openSettings
    }

    private func getNightModeAction() -> [PhotonRowActions] {
        var items: [PhotonRowActions] = []

        let nightModeEnabled = NightModeHelper.isActivated()
        let nightModeTitle: String = nightModeEnabled ? .AppMenu.AppMenuTurnOffNightMode : .AppMenu.AppMenuTurnOnNightMode
        let nightMode = SingleActionViewModel(title: nightModeTitle,
                                              iconString: ImageIdentifiers.nightMode,
                                              isEnabled: nightModeEnabled) { _ in
            NightModeHelper.toggle(tabManager: self.tabManager)

            if nightModeEnabled {
                TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .nightModeEnabled)
            } else {
                TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .nightModeDisabled)
            }

            // If we've enabled night mode and the theme is normal, enable dark theme
            if NightModeHelper.isActivated(), LegacyThemeManager.instance.currentName == .normal {
                LegacyThemeManager.instance.current = LegacyDarkTheme()
                self.themeManager.changeCurrentTheme(.dark)
                NightModeHelper.setEnabledDarkTheme(darkTheme: true)
            }

            // If we've disabled night mode and dark theme was activated by it then disable dark theme
            if !NightModeHelper.isActivated(), NightModeHelper.hasEnabledDarkTheme(), LegacyThemeManager.instance.currentName == .dark {
                LegacyThemeManager.instance.current = LegacyNormalTheme()
                self.themeManager.changeCurrentTheme(.light)
                NightModeHelper.setEnabledDarkTheme(darkTheme: false)
            }
        }.items
        items.append(nightMode)

        return items
    }

    private func syncMenuButton() -> PhotonRowActions? {
        let action: (SingleActionViewModel) -> Void = { [weak self] action in
            let fxaParams = FxALaunchParams(entrypoint: .browserMenu, query: [:])
            let parameters = FxASignInViewParameters(launchParameters: fxaParams,
                                                     flowType: .emailLoginFlow,
                                                     referringPage: .appMenu)
            self?.delegate?.showSignInView(fxaParameters: parameters)
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .signIntoSync)
        }

        let rustAccount = RustFirefoxAccounts.shared
        let needsReAuth = rustAccount.accountNeedsReauth()

        guard let userProfile = rustAccount.userProfile else {
            return SingleActionViewModel(title: .AppMenu.SyncAndSaveData,
                                         iconString: ImageIdentifiers.sync,
                                         tapHandler: action).items
        }

        let title: String = {
            if rustAccount.accountNeedsReauth() {
                return .FxAAccountVerifyPassword
            }
            return userProfile.displayName ?? userProfile.email
        }()

        let iconString = needsReAuth ? ImageIdentifiers.warning : StandardImageIdentifiers.Large.avatarCircle

        var iconURL: URL?
        if let str = rustAccount.userProfile?.avatarUrl, let url = URL(string: str) {
            iconURL = url
        }
        let iconType: PhotonActionSheetIconType = needsReAuth ? .Image : .URL
        let syncOption = SingleActionViewModel(title: title,
                                               iconString: iconString,
                                               iconURL: iconURL,
                                               iconType: iconType,
                                               needsIconActionableTint: needsReAuth,
                                               tapHandler: action).items
        return syncOption
    }

    // MARK: Whats New

    private func getWhatsNewAction() -> PhotonRowActions? {
        var whatsNewAction: PhotonRowActions?
        let showBadgeForWhatsNew = shouldShowWhatsNew()
        if showBadgeForWhatsNew {
            // Set the version number of the app, so the What's new will stop showing
            profile.prefs.setString(AppInfo.appVersion, forKey: PrefsKeys.AppVersion.Latest)

            // Redraw the toolbar so the badge hides from the appMenu button.
            delegate?.updateToolbarState()
        }

        whatsNewAction = SingleActionViewModel(title: .AppMenu.WhatsNewString,
                                               iconString: ImageIdentifiers.whatsNew,
                                               isEnabled: showBadgeForWhatsNew) { _ in
            if let whatsNewURL = SupportUtils.URLForWhatsNew {
                TelemetryWrapper.recordEvent(category: .action, method: .open, object: .whatsNew)
                self.delegate?.openURLInNewTab(whatsNewURL, isPrivate: false)
            }
        }.items
        return whatsNewAction
    }

    private func shouldShowWhatsNew() -> Bool {
        return isMajorVersionUpdate(using: profile) && DeviceInfo.hasConnectivity()
    }

    // MARK: Share

    private func getShareFileAction() -> PhotonRowActions {
        return SingleActionViewModel(title: .AppMenu.AppMenuSharePageTitleString,
                                     iconString: ImageIdentifiers.share) { _ in
            guard let tab = self.selectedTab,
                  let url = tab.url
            else { return }

            self.share(fileURL: url, buttonView: self.buttonView)
        }.items
    }

    private func getShareAction() -> PhotonRowActions {
        return SingleActionViewModel(title: .AppMenu.Share,
                                     iconString: ImageIdentifiers.share) { _ in
            guard let tab = self.selectedTab, let url = tab.canonicalURL?.displayURL else { return }

            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .sharePageWith)

            guard let temporaryDocument = tab.temporaryDocument else {
                if CoordinatorFlagManager.isShareExtensionCoordinatorEnabled {
                    self.navigationHandler?.showShareExtension(
                        url: url,
                        sourceView: self.buttonView,
                        toastContainer: self.toastContainer,
                        popoverArrowDirection: .any)
                } else {
                    self.delegate?.showMenuPresenter(url: url, tab: tab, view: self.buttonView)
                }
                return
            }

            temporaryDocument.getURL { tempDocURL in
                DispatchQueue.main.async {
                    // If we successfully got a temp file URL, share it like a downloaded file,
                    // otherwise present the ordinary share menu for the web URL.
                    if let tempDocURL = tempDocURL,
                       tempDocURL.isFileURL{
                        self.share(fileURL: tempDocURL, buttonView: self.buttonView)
                    } else {
                        if CoordinatorFlagManager.isShareExtensionCoordinatorEnabled {
                            self.navigationHandler?.showShareExtension(
                                url: url,
                                sourceView: self.buttonView,
                                toastContainer: self.toastContainer,
                                popoverArrowDirection: .any)
                        } else {
                            self.delegate?.showMenuPresenter(url: url, tab: tab, view: self.buttonView)
                        }
                    }
                }
            }
        }.items
    }

    // Main menu option Share page with when opening a file
    private func share(fileURL: URL, buttonView: UIView) {
        if CoordinatorFlagManager.isShareExtensionCoordinatorEnabled {
            navigationHandler?.showShareExtension(
                url: fileURL,
                sourceView: buttonView,
                toastContainer: toastContainer,
                popoverArrowDirection: .any)
        } else {
            let helper = ShareExtensionHelper(url: fileURL, tab: selectedTab)
            let controller = helper.createActivityViewController { _, _ in }

            if let popoverPresentationController = controller.popoverPresentationController {
                popoverPresentationController.sourceView = buttonView
                popoverPresentationController.sourceRect = buttonView.bounds
                popoverPresentationController.permittedArrowDirections = .up
            }
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .sharePageWith)
            delegate?.showViewController(viewController: controller)
        }
    }

    // MARK: Reading list

    private func getReadingListSection() -> [PhotonRowActions] {
        var section = [PhotonRowActions]()

        let libraryAction = getReadingListLibraryAction()
        if !isHomePage, selectedTab?.readerModeAvailableOrActive ?? false {
            let readingListAction = getReadingListAction()
            section.append(PhotonRowActions([libraryAction, readingListAction]))
        } else {
            section.append(PhotonRowActions(libraryAction))
        }

        return section
    }

    private func getReadingListLibraryAction() -> SingleActionViewModel {
        return SingleActionViewModel(title: .AppMenu.ReadingList,
                                     iconString: ImageIdentifiers.readingList) { _ in
            self.delegate?.showLibrary(panel: .readingList)
        }
    }

    private func getReadingListAction() -> SingleActionViewModel {
        return isInReadingList ? getRemoveReadingListAction() : getAddReadingListAction()
    }

    private func getAddReadingListAction() -> SingleActionViewModel {
        return SingleActionViewModel(title: .AppMenu.AddReadingList,
                                     iconString: ImageIdentifiers.addToReadingList) { _ in
            guard let tab = self.selectedTab,
                  let url = self.tabUrl?.displayURL
            else { return }

            self.profile.readingList.createRecordWithURL(url.absoluteString, title: tab.title ?? "", addedBy: UIDevice.current.name)
            TelemetryWrapper.recordEvent(category: .action, method: .add, object: .readingListItem, value: .pageActionMenu)
            self.delegate?.showToast(message: .AppMenu.AddToReadingListConfirmMessage, toastAction: .addToReadingList, url: nil)
        }
    }

    private func getRemoveReadingListAction() -> SingleActionViewModel {
        return SingleActionViewModel(title: .AppMenu.RemoveReadingList,
                                     iconString: StandardImageIdentifiers.Large.delete) { _ in
            guard let url = self.tabUrl?.displayURL?.absoluteString,
                  let record = self.profile.readingList.getRecordWithURL(url).value.successValue
            else { return }

            self.profile.readingList.deleteRecord(record, completion: nil)
            self.delegate?.showToast(message: .AppMenu.RemoveFromReadingListConfirmMessage,
                                     toastAction: .removeFromReadingList,
                                     url: nil)
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .delete,
                                         object: .readingListItem,
                                         value: .pageActionMenu)
        }
    }

    // MARK: Bookmark

    private func getBookmarkSection() -> [PhotonRowActions] {
        var section = [PhotonRowActions]()

        if !isHomePage {
            section.append(PhotonRowActions([getBookmarkLibraryAction(), getBookmarkAction()]))
        } else {
            section.append(PhotonRowActions(getBookmarkLibraryAction()))
        }

        return section
    }

    private func getBookmarkLibraryAction() -> SingleActionViewModel {
        return SingleActionViewModel(title: .AppMenu.Bookmarks,
                                     iconString: StandardImageIdentifiers.Large.bookmarkTrayFill) { _ in
            self.delegate?.showLibrary(panel: .bookmarks)
        }
    }

    private func getBookmarkAction() -> SingleActionViewModel {
        return isBookmarked ? getRemoveBookmarkAction() : getAddBookmarkAction()
    }

    private func getAddBookmarkAction() -> SingleActionViewModel {
        return SingleActionViewModel(title: .AppMenu.AddBookmark,
                                     iconString: StandardImageIdentifiers.Large.bookmark) { _ in
            guard let tab = self.selectedTab,
                  let url = tab.canonicalURL?.displayURL
            else { return }

            // The method in BVC also handles the toast for this use case
            self.delegate?.addBookmark(url: url.absoluteString, title: tab.title)
            TelemetryWrapper.recordEvent(category: .action, method: .add, object: .bookmark, value: .pageActionMenu)
        }
    }

    private func getRemoveBookmarkAction() -> SingleActionViewModel {
        return SingleActionViewModel(title: .AppMenu.RemoveBookmark,
                                     iconString: StandardImageIdentifiers.Large.bookmarkSlash) { _ in
            guard let url = self.tabUrl?.displayURL else { return }

            self.profile.places.deleteBookmarksWithURL(url: url.absoluteString).uponQueue(.main) { result in
                guard result.isSuccess else { return }
                self.delegate?.showToast(message: .AppMenu.RemoveBookmarkConfirmMessage, toastAction: .removeBookmark, url: url.absoluteString)
                self.removeBookmarkShortcut()
            }

            TelemetryWrapper.recordEvent(category: .action, method: .delete, object: .bookmark, value: .pageActionMenu)
        }
    }

    // MARK: Shortcut

    private func getShortcutAction() -> PhotonRowActions {
        return isPinned ? getRemoveShortcutAction().items : getAddShortcutAction().items
    }

    private func getAddShortcutAction() -> SingleActionViewModel {
        return SingleActionViewModel(title: .AddToShortcutsActionTitle,
                                     iconString: StandardImageIdentifiers.Large.pin) { _ in
            guard let url = self.selectedTab?.url?.displayURL,
                  let title = self.selectedTab?.displayTitle else { return }
            let site = Site(url: url.absoluteString, title: title)
            self.profile.pinnedSites.addPinnedTopSite(site).uponQueue(.main) { result in
                guard result.isSuccess else { return }
                self.delegate?.showToast(message: .AppMenu.AddPinToShortcutsConfirmMessage, toastAction: .pinPage, url: nil)
            }

            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .pinToTopSites)
        }
    }

    private func getRemoveShortcutAction() -> SingleActionViewModel {
        return SingleActionViewModel(title: .AppMenu.RemoveFromShortcuts,
                                     iconString: StandardImageIdentifiers.Large.pinSlash) { _ in
            guard let url = self.selectedTab?.url?.displayURL,
                  let title = self.selectedTab?.displayTitle else { return }
            let site = Site(url: url.absoluteString, title: title)
            self.profile.pinnedSites.removeFromPinnedTopSites(site).uponQueue(.main) { result in
                if result.isSuccess {
                    self.delegate?.showToast(message: .AppMenu.RemovePinFromShortcutsConfirmMessage, toastAction: .removePinPage, url: nil)
                }
            }
            TelemetryWrapper.recordEvent(category: .action, method: .tap, object: .removePinnedSite)
        }
    }

    // MARK: Password

    private func getPasswordAction(navigationController: UINavigationController?) -> PhotonRowActions? {
        guard PasswordManagerListViewController.shouldShowAppMenuShortcut(forPrefs: profile.prefs) else { return nil }

        return SingleActionViewModel(title: .AppMenu.AppMenuPasswords,
                                     iconString: StandardImageIdentifiers.Large.login,
                                     iconType: .Image,
                                     iconAlignment: .left) { _ in
            self.navigationHandler?.show(settings: .password)
        }.items
    }

    // MARK: - Conveniance

    private func append(to items: inout [PhotonRowActions], action: PhotonRowActions?) {
        if let action = action {
            items.append(action)
        }
    }

    private func append(to items: inout [PhotonRowActions], action: [PhotonRowActions]?) {
        if let action = action {
            items.append(contentsOf: action)
        }
    }
}
