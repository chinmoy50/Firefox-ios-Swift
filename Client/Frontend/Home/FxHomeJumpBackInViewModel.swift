// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
import Storage

struct JumpList {
    let group: ASGroup<Tab>?
    let tabs: [Tab]
    var itemsToDisplay: Int {
        get {
            var count = 0

            count += group != nil ? 1 : 0
            count += tabs.count

            return count
        }
    }
}

class FirefoxHomeJumpBackInViewModel: FeatureFlagsProtocol {

    // MARK: - Properties

    var jumpList = JumpList(group: nil, tabs: [Tab]())
    var onTapGroup: ((Tab) -> Void)?

    private lazy var siteImageHelper = SiteImageHelper(profile: profile)
    private let isZeroSearch: Bool
    private let profile: Profile
    private let tabManager: TabManager

    init(isZeroSearch: Bool = false,
         profile: Profile,
         tabManager: TabManager = BrowserViewController.foregroundBVC().tabManager) {

        self.profile = profile
        self.isZeroSearch = isZeroSearch
        self.tabManager = tabManager
    }

    static var maxItemsToDisplay: Int {
        if deviceIsiPad {
            return 3 // iPad
        } else if deviceIsInLandscapeMode {
            return 4 // iPhone in landscape
        } else {
            return 2 // iPhone in portrait
        }
    }

    static var numberOfItemsInColumn: Int {
        return deviceIsiPad ? 1 : 2
    }

    static var widthDimension: NSCollectionLayoutDimension {
        if deviceIsiPad && deviceIsInLandscapeMode {
            return .fractionalWidth(1/3) // iPad in landscape
        } else if deviceIsiPad {
            return .fractionalWidth(1) // iPad in portrait
        } else if deviceIsInLandscapeMode {
            return .fractionalWidth(1/2) // iPhone in landscape
        } else {
            return .fractionalWidth(1) // iPhone in portrait
        }
    }

    func updateData(completion: @escaping () -> Void) {
        if featureFlags.isFeatureActiveForBuild(.groupedTabs),
           featureFlags.userPreferenceFor(.groupedTabs) == UserFeaturePreference.enabled {
            let recentTabs = tabManager.recentlyAccessedNormalTabs
            SearchTermGroupsManager.getTabGroups(with: profile,
                                          from: recentTabs,
                                          using: .orderedDescending) { [weak self] groups, _ in
                guard let strongSelf = self else { completion(); return }
                strongSelf.jumpList = strongSelf.createJumpList(from: recentTabs, and: groups)
                completion()
            }
        } else {
            jumpList = createJumpList(from: tabManager.recentlyAccessedNormalTabs)
            completion()
        }
    }

    func switchTo(group: ASGroup<Tab>) {
        if BrowserViewController.foregroundBVC().urlBar.inOverlayMode {
            BrowserViewController.foregroundBVC().urlBar.leaveOverlayMode()
        }
        guard let firstTab = group.groupedItems.first else { return }

        onTapGroup?(firstTab)

        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .firefoxHomepage,
                                     value: .jumpBackInSectionGroupOpened,
                                     extras: TelemetryWrapper.getOriginExtras(isZeroSearch: isZeroSearch))
    }

    func switchTo(tab: Tab) {
        if BrowserViewController.foregroundBVC().urlBar.inOverlayMode {
            BrowserViewController.foregroundBVC().urlBar.leaveOverlayMode()
        }
        tabManager.selectTab(tab)
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .firefoxHomepage,
                                     value: .jumpBackInSectionTabOpened,
                                     extras: TelemetryWrapper.getOriginExtras(isZeroSearch: isZeroSearch))
    }

    func getFaviconImage(forSite site: Site, completion: @escaping (UIImage?) -> Void) {
        siteImageHelper.fetchImageFor(site: site, imageType: .favicon, shouldFallback: false) { image in
            completion(image)
        }
    }

    func getHeroImage(forSite site: Site, completion: @escaping (UIImage?) -> Void) {
        siteImageHelper.fetchImageFor(site: site, imageType: .heroImage, shouldFallback: false) { image in
            completion(image)
        }
    }

    // MARK: - Private

    private func createJumpList(from tabs: [Tab], and groups: [ASGroup<Tab>]? = nil) -> JumpList {
        let recentGroup = groups?.first
        let groupCount = recentGroup != nil ? 1 : 0
        let recentTabs = filter(tabs: tabs, from: recentGroup, usingGroupCount: groupCount)

        return JumpList(group: recentGroup, tabs: recentTabs)
    }

    private func filter(tabs: [Tab], from recentGroup: ASGroup<Tab>?, usingGroupCount groupCount: Int) -> [Tab] {
        var recentTabs = [Tab]()
        let maxItemCount = FirefoxHomeJumpBackInViewModel.maxItemsToDisplay - groupCount

        for tab in tabs {
            // We must make sure to not include any 'solo' tabs that are also part of a group
            // because they should not show up in the Jump Back In section.
            if let recentGroup = recentGroup, recentGroup.groupedItems.contains(tab) { continue }

            recentTabs.append(tab)
            // We are only showing one group in Jump Back in, so adjust count accordingly
            if recentTabs.count == maxItemCount { break }
        }

        return recentTabs
    }

    private static var deviceIsiPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private static var deviceIsInLandscapeMode: Bool {
        UIWindow.isLandscape
    }
}
