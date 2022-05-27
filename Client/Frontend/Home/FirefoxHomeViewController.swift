// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Shared
import UIKit
import Storage
import SyncTelemetry
import MozillaAppServices

class FirefoxHomeViewController: UICollectionViewController, HomePanel, GleanPlumbMessageManagable {
    // MARK: - Typealiases
    private typealias a11y = AccessibilityIdentifiers.FirefoxHomepage

    // MARK: - Operational Variables
    weak var homePanelDelegate: HomePanelDelegate?
    weak var libraryPanelDelegate: LibraryPanelDelegate?
    var notificationCenter: NotificationCenter = NotificationCenter.default

    private var hasSentJumpBackInSectionEvent = false
    private var isZeroSearch: Bool
    private var viewModel: FirefoxHomeViewModel
    private var contextMenuHelper: FirefoxHomeContextMenuHelper

    private var wallpaperManager: WallpaperManager
    private lazy var wallpaperView: WallpaperBackgroundView = .build { _ in }
    private var contextualHintViewController: ContextualHintViewController

    lazy var homeTabBanner: HomeTabBanner = .build { card in
        card.backgroundColor = UIColor.theme.homePanel.topSitesBackground
    }

    var currentTab: Tab? {
        let tabManager = BrowserViewController.foregroundBVC().tabManager
        return tabManager.selectedTab
    }

    // MARK: - Initializers
    init(profile: Profile,
         isZeroSearch: Bool = false,
         wallpaperManager: WallpaperManager = WallpaperManager()
    ) {
        self.isZeroSearch = isZeroSearch
        self.wallpaperManager = wallpaperManager
        let isPrivate = BrowserViewController.foregroundBVC().tabManager.selectedTab?.isPrivate ?? true
        self.viewModel = FirefoxHomeViewModel(profile: profile,
                                              isZeroSearch: isZeroSearch,
                                              isPrivate: isPrivate)
        let contextualViewModel = ContextualHintViewModel(forHintType: .jumpBackIn,
                                                          with: viewModel.profile)
        self.contextualHintViewController = ContextualHintViewController(with: contextualViewModel)
        self.contextMenuHelper = FirefoxHomeContextMenuHelper(viewModel: viewModel)

        super.init(collectionViewLayout: FirefoxHomeViewController.createLayout())

        contextMenuHelper.delegate = self
        contextMenuHelper.getPopoverSourceRect = { [weak self] popoverView in
            guard let self = self else { return CGRect() }
            return self.getPopoverSourceRect(sourceView: popoverView)
        }

        viewModel.delegate = self
        collectionView?.delegate = self
        collectionView?.dataSource = self
        collectionView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // TODO: .TabClosed notif should be in JumpBackIn view only to reload it's data, but can't right now since doesn't self-size
        setupNotifications(forObserver: self,
                           observing: [.HomePanelPrefsChanged,
                                       .TopTabsTabClosed,
                                       .TabsTrayDidClose,
                                       .TabsTrayDidSelectHomeTab,
                                       .TabsPrivacyModeChanged])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        contextualHintViewController.stopTimer()
        notificationCenter.removeObserver(self)
    }

    // MARK: - View lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        FirefoxHomeSectionType.allCases.forEach {
            collectionView.register($0.cellType, forCellWithReuseIdentifier: $0.cellIdentifier)
        }
        collectionView?.register(ASHeaderView.self,
                                 forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                 withReuseIdentifier: ASHeaderView.cellIdentifier)
        collectionView?.keyboardDismissMode = .onDrag
        collectionView?.backgroundColor = .clear
        view.addSubview(wallpaperView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        if shouldDisplayHomeTabBanner {
            showHomeTabBanner()
        }

        NSLayoutConstraint.activate([
            wallpaperView.topAnchor.constraint(equalTo: view.topAnchor),
            wallpaperView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wallpaperView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            wallpaperView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        view.sendSubviewToBack(wallpaperView)

        applyTheme()
        setupSectionsAction()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadAll()
    }

    override func viewDidAppear(_ animated: Bool) {
        viewModel.recordViewAppeared()
        animateFirefoxLogo()

        super.viewDidAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        contextualHintViewController.stopTimer()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        reloadOnRotation(with: coordinator)
        wallpaperView.updateImageForOrientationChange()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }

    // MARK: - Layout

    static func createLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout {
            (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            // TODO: Laurie pass in the traitCollection from layoutEnvironment?
            guard let section = FirefoxHomeSectionType(rawValue: sectionIndex)?.section else {
                return nil
            }

            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: FirefoxHomeViewModel.UX.standardLeadingInset,
                                                            bottom: 0, trailing: 0)
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                    heightDimension: .estimated(100))
            let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                                     elementKind: UICollectionView.elementKindSectionHeader,
                                                                     alignment: .top)
            section.boundarySupplementaryItems = [header]

            return section
        }
        return layout
    }

    // MARK: - Helpers

    private func reloadOnRotation(with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { context in
            // The AS context menu does not behave correctly. Dismiss it when rotating.
            if let _ = self.presentedViewController as? PhotonActionSheet {
                self.presentedViewController?.dismiss(animated: true, completion: nil)
            }
            self.collectionViewLayout.invalidateLayout()
            self.collectionView?.reloadData()
        }, completion: { _ in
            // TODO: Laurie still necessary to reload here?
            // Workaround: label positions are not correct without additional reload
            self.collectionView?.reloadData()
        })
    }

    private func adjustPrivacySensitiveSections(notification: Notification) {
        guard let dict = notification.object as? NSDictionary,
              let isPrivate = dict[Tab.privateModeKey] as? Bool
        else { return }

        viewModel.isPrivate = isPrivate
        if let jumpBackIndex = viewModel.enabledSections.firstIndex(of: FirefoxHomeSectionType.jumpBackIn) {
            let indexSet = IndexSet([jumpBackIndex])
            collectionView.reloadSections(indexSet)
        }

        if let highlightIndex = viewModel.enabledSections.firstIndex(of: FirefoxHomeSectionType.historyHighlights) {
            let indexSet = IndexSet([highlightIndex])
            collectionView.reloadSections(indexSet)
        } else {
            reloadAll()
        }
    }

    func applyTheme() {
        homeTabBanner.applyTheme()
        view.backgroundColor = UIColor.theme.homePanel.topSitesBackground
    }

    func scrollToTop(animated: Bool = false) {
        collectionView?.setContentOffset(.zero, animated: animated)
    }

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        dismissKeyboard()
    }

    @objc private func dismissKeyboard() {
        currentTab?.lastKnownUrl?.absoluteString.hasPrefix("internal://") ?? false ? BrowserViewController.foregroundBVC().urlBar.leaveOverlayMode() : nil
    }

    private func showSiteWithURLHandler(_ url: URL, isGoogleTopSite: Bool = false) {
        let visitType = VisitType.bookmark
        homePanelDelegate?.homePanel(didSelectURL: url, visitType: visitType, isGoogleTopSite: isGoogleTopSite)
    }

    private func animateFirefoxLogo() {
        guard viewModel.headerViewModel.shouldRunLogoAnimation(),
              let cell = collectionView.cellForItem(at: IndexPath(row: 0, section: 0)) as? FxHomeLogoHeaderCell
        else { return }

        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: false, block: { _ in
            cell.runLogoAnimation()
        })
    }

    // MARK: - Contextual hint
    private func prepareJumpBackInContextualHint(onView headerView: ASHeaderView) {
        guard contextualHintViewController.shouldPresentHint(),
              !shouldDisplayHomeTabBanner
        else { return }

        contextualHintViewController.configure(
            anchor: headerView.titleLabel,
            withArrowDirection: .down,
            andDelegate: self,
            presentedUsing: { self.presentContextualHint() },
            withActionBeforeAppearing: { self.contextualHintPresented() },
            andActionForButton: { self.openTabsSettings() })
    }

    @objc private func presentContextualHint() {
        guard BrowserViewController.foregroundBVC().searchController == nil,
              presentedViewController == nil
        else {
            contextualHintViewController.stopTimer()
            return
        }

        present(contextualHintViewController, animated: true, completion: nil)
    }

    // MARK: - Home Tab Banner

    private var shouldDisplayHomeTabBanner: Bool {
        let message = messagingManager.getNextMessage(for: .newTabCard)
        if #available(iOS 14.0, *), message != nil || !UserDefaults.standard.bool(forKey: PrefsKeys.DidDismissDefaultBrowserMessage) {
            return true
        } else {
            return false
        }
    }

    private func showHomeTabBanner() {
        view.addSubview(homeTabBanner)
        NSLayoutConstraint.activate([
            homeTabBanner.topAnchor.constraint(equalTo: view.topAnchor),
            homeTabBanner.bottomAnchor.constraint(equalTo: collectionView.topAnchor),
            homeTabBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            homeTabBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            homeTabBanner.heightAnchor.constraint(equalToConstant: 264),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        homeTabBanner.dismissClosure = { [weak self] in
            self?.dismissHomeTabBanner()
        }
    }

    public func dismissHomeTabBanner() {
        homeTabBanner.removeFromSuperview()
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}

// MARK: -  CollectionView Data Source

 extension FirefoxHomeViewController {

     override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
         guard kind == UICollectionView.elementKindSectionHeader,
               let headerView = collectionView.dequeueReusableSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader,
                withReuseIdentifier: ASHeaderView.cellIdentifier,
                for: indexPath) as? ASHeaderView
         else {
             return UICollectionReusableView()
         }

         // Jump back in header specific setup
         if FirefoxHomeSectionType(indexPath.section) == .jumpBackIn {
             if !hasSentJumpBackInSectionEvent {
                 TelemetryWrapper.recordEvent(category: .action,
                                              method: .view,
                                              object: .jumpBackInImpressions,
                                              value: nil,
                                              extras: nil)
                 hasSentJumpBackInSectionEvent = true
             }
             prepareJumpBackInContextualHint(onView: headerView)
         }

         // Configure header only if section is shown
         let viewModel = viewModel.getSectionViewModel(section: indexPath.section)
         let headerViewModel = viewModel.shouldShow ? viewModel.headerViewModel : ASHeaderViewModel.emptyHeader
         headerView.configure(viewModel: headerViewModel)
         return headerView
     }
 }

//
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
//        // This removes extra space since insetForSectionAt is called for all sections even if they are not showing
//        // Root cause is that numberOfSections is always returned as FirefoxHomeSectionType.allCases
//        let sideInsets = FirefoxHomeSectionType(section).sectionInsets(self.traitCollection, frameWidth: self.view.frame.width)
//        let edgeInsets = UIEdgeInsets(top: 0, left: sideInsets, bottom: FirefoxHomeViewModel.UX.spacingBetweenSections, right: sideInsets)
//
//        switch FirefoxHomeSectionType(section) {
//        case .logoHeader:
//            return viewModel.headerViewModel.shouldShow ? edgeInsets : .zero
//        case .pocket:
//            return viewModel.pocketViewModel.shouldShow ? edgeInsets : .zero
//        case .topSites:
//            return viewModel.topSiteViewModel.shouldShow ? edgeInsets : .zero
//        case .jumpBackIn:
//            return viewModel.jumpBackInViewModel.shouldShow ? edgeInsets : .zero
//        case .historyHighlights:
//            return viewModel.historyHighlightsViewModel.shouldShow ? edgeInsets : .zero
//        case .recentlySaved:
//            return viewModel.recentlySavedViewModel.shouldShow ? edgeInsets : .zero
//        default:
//            return .zero
//        }
//    }
// }

// MARK: - CollectionView Data Source

extension FirefoxHomeViewController {

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return FirefoxHomeSectionType.allCases.count
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.updateEnabledSections()
        return viewModel.getSectionViewModel(section: section).numberOfItemsInSection
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let identifier = FirefoxHomeSectionType(indexPath.section).cellIdentifier
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath)

        // TODO: Laurie - Change this to protocol comformance instead of switch
        switch FirefoxHomeSectionType(indexPath.section) {
        case .logoHeader:
            return viewModel.headerViewModel.configure(cell, at: indexPath)

        case .topSites:
            return configureTopSitesCell(cell, forIndexPath: indexPath)

        case .pocket:
            return configurePocketItemCell(cell, forIndexPath: indexPath)

        case .jumpBackIn:
            return configureJumpBackInCell(cell, forIndexPath: indexPath)

        case .recentlySaved:
            return viewModel.recentlySavedViewModel.configure(cell, at: indexPath)

        case .historyHighlights:
            return configureHistoryHighlightsCell(cell, forIndexPath: indexPath)

        case .customizeHome:
            return viewModel.customizeButtonViewModel.configure(cell, at: indexPath)
        }
    }

    func configureTopSitesCell(_ cell: UICollectionViewCell, forIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        guard let topSiteCell = cell as? TopSiteCollectionCell else { return UICollectionViewCell() }
        topSiteCell.viewModel = viewModel.topSiteViewModel
        topSiteCell.reloadLayout()
        topSiteCell.setNeedsLayout()

        return cell
    }

    private func configurePocketItemCell(_ cell: UICollectionViewCell, forIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        guard let pocketCell = cell as? FxHomePocketCollectionCell else { return UICollectionViewCell() }

        viewModel.pocketViewModel.recordSectionHasShown()
        pocketCell.viewModel = viewModel.pocketViewModel
        pocketCell.reloadLayout()
        pocketCell.setNeedsLayout()

        return pocketCell
    }

    private func configureJumpBackInCell(_ cell: UICollectionViewCell, forIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        guard let jumpBackInCell = cell as? FxHomeJumpBackInCollectionCell else { return UICollectionViewCell() }
        jumpBackInCell.viewModel = viewModel.jumpBackInViewModel

        jumpBackInCell.reloadLayout()
        jumpBackInCell.setNeedsLayout()

        return jumpBackInCell
    }

    private func configureHistoryHighlightsCell(_ cell: UICollectionViewCell, forIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        guard let historyCell = cell as? FxHomeHistoryHighlightsCollectionCell else { return UICollectionViewCell() }

        guard let items = viewModel.historyHighlightsViewModel.historyItems, !items.isEmpty else { return UICollectionViewCell() }

        historyCell.viewModel = viewModel.historyHighlightsViewModel
        historyCell.viewModel?.recordSectionHasShown()
        historyCell.reloadLayout()
        historyCell.setNeedsLayout()

        return historyCell
    }

    private func openHistoryHighligtsSearchGroup(item: HighlightItem) {
        guard let groupItem = item.group else { return }

        var groupedSites = [Site]()
        for item in groupItem {
            groupedSites.append(buildSite(from: item))
        }
        let groupSite = ASGroup<Site>(searchTerm: item.displayTitle, groupedItems: groupedSites, timestamp: Date.now())

        let asGroupListViewModel = SearchGroupedItemsViewModel(asGroup: groupSite, presenter: .recentlyVisited)
        let asGroupListVC = SearchGroupedItemsViewController(viewModel: asGroupListViewModel, profile: viewModel.profile)

        let dismissableController: DismissableNavigationViewController
        dismissableController = DismissableNavigationViewController(rootViewController: asGroupListVC)

        self.present(dismissableController, animated: true, completion: nil)

        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .firefoxHomepage,
                                     value: .historyHighlightsGroupOpen,
                                     extras: nil)

        asGroupListVC.libraryPanelDelegate = libraryPanelDelegate
    }

    private func buildSite(from highlight: HighlightItem) -> Site {
        let itemURL = highlight.siteUrl?.absoluteString ?? ""
        return Site(url: itemURL, title: highlight.displayTitle)
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        switch FirefoxHomeSectionType(indexPath.section) {
        case .recentlySaved:
            viewModel.recentlySavedViewModel.didSelectItem(at: indexPath,
                                                           homePanelDelegate: homePanelDelegate,
                                                           libraryPanelDelegate: libraryPanelDelegate)
        default:
            break
        }
    }
}

// MARK: - Data Management

extension FirefoxHomeViewController {

    /// Reload all data including refreshing cells content and fetching data from backend
    func reloadAll() {
        DispatchQueue.global(qos: .userInteractive).async {
            self.viewModel.updateData()
            // Collection view should only actually reload its data once the various
            // sections have data to display. As such, it must be done after the
            // `updateData` call, which is, itself, async.
            DispatchQueue.main.async {
                self.collectionView.reloadData()
            }
        }
    }
}

// MARK: - Actions Handling

private extension FirefoxHomeViewController {

    // Setup all the tap and long press actions on cells in each sections
    private func setupSectionsAction() {

        // Header view
        viewModel.headerViewModel.onTapAction = { [weak self] _ in
            self?.changeHomepageWallpaper()
        }

        // Top sites
        viewModel.topSiteViewModel.tilePressedHandler = { [weak self] site, isGoogle in
            guard let url = site.url.asURL else { return }
            self?.showSiteWithURLHandler(url, isGoogleTopSite: isGoogle)
        }

        viewModel.topSiteViewModel.tileLongPressedHandler = { [weak self] (site, sourceView) in
            self?.contextMenuHelper.presentContextMenu(for: site, with: sourceView, sectionType: .topSites)
        }

        // Recently saved
        viewModel.recentlySavedViewModel.headerButtonAction = { [weak self] button in
            self?.openBookmarks(button)
        }

        // Jumpback in
        viewModel.jumpBackInViewModel.onTapGroup = { [weak self] tab in
            self?.homePanelDelegate?.homePanelDidRequestToOpenTabTray(withFocusedTab: tab)
        }

        viewModel.jumpBackInViewModel.headerButtonAction = { [weak self] button in
            self?.openTabTray(button)
        }

        // History highlights
        viewModel.historyHighlightsViewModel.onTapItem = { [weak self] highlight in
            guard let url = highlight.siteUrl else {
                self?.openHistoryHighligtsSearchGroup(item: highlight)
                return
            }

            self?.homePanelDelegate?.homePanel(didSelectURL: url, visitType: .link, isGoogleTopSite: false)
        }

        viewModel.historyHighlightsViewModel.headerButtonAction = { [weak self] button in
            self?.openHistory(button)
        }

        // Pocket
        viewModel.pocketViewModel.onTapTileAction = { [weak self] url in
            self?.showSiteWithURLHandler(url)
        }

        viewModel.pocketViewModel.onLongPressTileAction = { [weak self] (site, sourceView) in
            self?.contextMenuHelper.presentContextMenu(for: site, with: sourceView, sectionType: .pocket)
        }

        // Customize home
        viewModel.customizeButtonViewModel.onTapAction = { [weak self] _ in
            self?.openCustomizeHomeSettings()
        }
    }

    @objc func openTabTray(_ sender: UIButton) {
        if sender.accessibilityIdentifier == a11y.MoreButtons.jumpBackIn {
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .jumpBackInSectionShowAll,
                                         extras: TelemetryWrapper.getOriginExtras(isZeroSearch: isZeroSearch))
        }
        homePanelDelegate?.homePanelDidRequestToOpenTabTray(withFocusedTab: nil)
    }

    @objc func openBookmarks(_ sender: UIButton) {
        homePanelDelegate?.homePanelDidRequestToOpenLibrary(panel: .bookmarks)

        if sender.accessibilityIdentifier == a11y.MoreButtons.recentlySaved {
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .recentlySavedSectionShowAll,
                                         extras: TelemetryWrapper.getOriginExtras(isZeroSearch: isZeroSearch))
        } else {
            // TODO: Laurie - remove
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .yourLibrarySection,
                                         extras: [TelemetryWrapper.EventObject.libraryPanel.rawValue: TelemetryWrapper.EventValue.bookmarksPanel.rawValue])
        }
    }

    @objc func openHistory(_ sender: UIButton) {
        homePanelDelegate?.homePanelDidRequestToOpenLibrary(panel: .history)
        if sender.accessibilityIdentifier == a11y.MoreButtons.historyHighlights {
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .historyHighlightsShowAll)

        } else {
            // TODO: Laurie - remove
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .tap,
                                         object: .firefoxHomepage,
                                         value: .yourLibrarySection,
                                         extras: [TelemetryWrapper.EventObject.libraryPanel.rawValue: TelemetryWrapper.EventValue.historyPanel.rawValue])
        }
    }

    // TODO: Laurie - remove
//    @objc func openReadingList(_ sender: UIButton) {
//        homePanelDelegate?.homePanelDidRequestToOpenLibrary(panel: .readingList)
//        TelemetryWrapper.recordEvent(category: .action,
//                                     method: .tap,
//                                     object: .firefoxHomepage,
//                                     value: .yourLibrarySection,
//                                     extras: [TelemetryWrapper.EventObject.libraryPanel.rawValue: TelemetryWrapper.EventValue.readingListPanel.rawValue])
//    }

//    @objc func openDownloads(_ sender: UIButton) {
//        homePanelDelegate?.homePanelDidRequestToOpenLibrary(panel: .downloads)
//        TelemetryWrapper.recordEvent(category: .action,
//                                     method: .tap,
//                                     object: .firefoxHomepage,
//                                     value: .yourLibrarySection,
//                                     extras: [TelemetryWrapper.EventObject.libraryPanel.rawValue: TelemetryWrapper.EventValue.downloadsPanel.rawValue])
//    }

    func openCustomizeHomeSettings() {
        homePanelDelegate?.homePanelDidRequestToOpenSettings(at: .customizeHomepage)
        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: .firefoxHomepage,
                                     value: .customizeHomepageButton)
    }

    func contextualHintPresented() {
        homePanelDelegate?.homePanelDidPresentContextualHintOf(type: .jumpBackIn)
    }

    func openTabsSettings() {
        homePanelDelegate?.homePanelDidRequestToOpenSettings(at: .customizeTabs)
    }

    func changeHomepageWallpaper() {
        wallpaperView.cycleWallpaper()
    }

    func getPopoverSourceRect(sourceView: UIView?) -> CGRect {
        let cellRect = sourceView?.frame ?? .zero
        let cellFrameInSuperview = self.collectionView?.convert(cellRect, to: self.collectionView) ?? .zero

        return CGRect(origin: CGPoint(x: cellFrameInSuperview.size.width / 2,
                                      y: cellFrameInSuperview.height / 2),
                      size: .zero)
    }
}

// MARK: FirefoxHomeContextMenuHelperDelegate
extension FirefoxHomeViewController: FirefoxHomeContextMenuHelperDelegate {
    func homePanelDidRequestToOpenInNewTab(_ url: URL, isPrivate: Bool, selectNewTab: Bool) {
        homePanelDelegate?.homePanelDidRequestToOpenInNewTab(url, isPrivate: isPrivate, selectNewTab: selectNewTab)
    }

    func homePanelDidRequestToOpenSettings(at settingsPage: AppSettingsDeeplinkOption) {
        homePanelDelegate?.homePanelDidRequestToOpenSettings(at: settingsPage)
    }
}

// MARK: - Popover Presentation Delegate

extension FirefoxHomeViewController: UIPopoverPresentationControllerDelegate {

    // Dismiss the popover if the device is being rotated.
    // This is used by the Share UIActivityViewController action sheet on iPad
    func popoverPresentationController(_ popoverPresentationController: UIPopoverPresentationController, willRepositionPopoverTo rect: UnsafeMutablePointer<CGRect>, in view: AutoreleasingUnsafeMutablePointer<UIView>) {
        // Do not dismiss if the popover is a CFR
        if contextualHintViewController.isPresenting { return }
        popoverPresentationController.presentedViewController.dismiss(animated: false, completion: nil)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        return true
    }
}

// MARK: FirefoxHomeViewModelDelegate
extension FirefoxHomeViewController: FirefoxHomeViewModelDelegate {
    func reloadSection(index: Int?) {
        DispatchQueue.main.async {
            if let index = index {
                let indexSet = IndexSet([index])
                self.collectionView.reloadSections(indexSet)
            } else {
                self.collectionView.reloadData()
            }
        }
    }
}

// MARK: - Notifiable
extension FirefoxHomeViewController: Notifiable {
    func handleNotifications(_ notification: Notification) {
        ensureMainThread { [weak self] in
            switch notification.name {
            case .TabsPrivacyModeChanged:
                self?.adjustPrivacySensitiveSections(notification: notification)
            case .TabsTrayDidClose,
                    .TopTabsTabClosed,
                    .TabsTrayDidSelectHomeTab:
                self?.reloadAll()
            case .HomePanelPrefsChanged:
                self?.reloadAll()
            default: break
            }
        }
    }
}
