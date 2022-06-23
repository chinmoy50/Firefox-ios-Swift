// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import UIKit
import Storage
import Shared
import XCGLogger

private let log = Logger.browserLogger

let LocalizedRootBookmarkFolderStrings = [
    BookmarkRoots.MenuFolderGUID: String.BookmarksFolderTitleMenu,
    BookmarkRoots.ToolbarFolderGUID: String.BookmarksFolderTitleToolbar,
    BookmarkRoots.UnfiledFolderGUID: String.BookmarksFolderTitleUnsorted,
    BookmarkRoots.MobileFolderGUID: String.BookmarksFolderTitleMobile,
    LocalDesktopFolder.localDesktopFolderGuid: String.Bookmarks.Menu.DesktopBookmarks
]

private class SeparatorTableViewCell: OneLineTableViewCell {
    override func applyTheme() {
        super.applyTheme()

        backgroundColor = UIColor.theme.tableView.headerBackground
    }
}

class BookmarksPanel: SiteTableViewController, LibraryPanel, CanRemoveQuickActionBookmark {

    private struct UX {
        static let FolderIconSize = CGSize(width: 24, height: 24)
        static let RowFlashDelay: TimeInterval = 0.4
    }

    private enum BookmarksSection: Int, CaseIterable {
        case bookmarks
    }

    // MARK: - Properties
    var libraryPanelDelegate: LibraryPanelDelegate?
    var notificationCenter = NotificationCenter.default

    private let bookmarkFolderGUID: GUID
    private var bookmarkFolder: BookmarkFolderData?
    private var bookmarkNodes = [FxBookmarkNode]()
    private var chevronImage = UIImage(named: ImageIdentifiers.menuChevron)
    private var flashLastRowOnNextReload = false

    private lazy var bookmarkFolderIconNormal = {
        return UIImage(named: ImageIdentifiers.bookmarkFolder)?
            .createScaled(UX.FolderIconSize)
            .tinted(withColor: UIColor.Photon.Grey90)
    }()

    private lazy var bookmarkFolderIconDark = {
        return UIImage(named: ImageIdentifiers.bookmarkFolder)?
            .createScaled(UX.FolderIconSize)
            .tinted(withColor: UIColor.Photon.Grey10)
    }()

    init(profile: Profile, bookmarkFolderGUID: GUID = BookmarkRoots.RootGUID) {
        self.bookmarkFolderGUID = bookmarkFolderGUID

        super.init(profile: profile)

        setupNotifications(forObserver: self, observing: [.FirefoxAccountChanged])

        tableView.register(cellType: OneLineTableViewCell.self)
        tableView.register(cellType: SeparatorTableViewCell.self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let tableViewLongPressRecognizer = UILongPressGestureRecognizer(target: self,
                                                                        action: #selector(didLongPressTableView))
        tableView.addGestureRecognizer(tableViewLongPressRecognizer)
        tableView.accessibilityIdentifier = AccessibilityIdentifiers.LibraryPanels.BookmarksPanel.tableView
        tableView.allowsSelectionDuringEditing = true
        tableView.backgroundColor = UIColor.theme.homePanel.panelBackground
    }

    func addNewBookmarkItemAction() {
        let newBookmark = SingleActionViewModel(title: .BookmarksNewBookmark,
                                                iconString: ImageIdentifiers.actionAddBookmark,
                                                tapHandler: { _ in
            guard let bookmarkFolder = self.bookmarkFolder else {
                return
            }

            let detailController = BookmarkDetailPanel(profile: self.profile,
                                                       withNewBookmarkNodeType: .bookmark,
                                                       parentBookmarkFolder: bookmarkFolder)
            self.navigationController?.pushViewController(detailController, animated: true)
        }).items

        let newFolder = SingleActionViewModel(title: .BookmarksNewFolder,
                                              iconString: ImageIdentifiers.bookmarkFolder,
                                              tapHandler: { _ in
            guard let bookmarkFolder = self.bookmarkFolder else {
                return
            }

            let detailController = BookmarkDetailPanel(profile: self.profile,
                                                       withNewBookmarkNodeType: .folder,
                                                       parentBookmarkFolder: bookmarkFolder)
            self.navigationController?.pushViewController(detailController, animated: true)
        }).items

        let newSeparator = SingleActionViewModel(title: .BookmarksNewSeparator,
                                                 iconString: ImageIdentifiers.navMenu,
                                                 tapHandler: { _ in
            let centerVisibleRow = self.centerVisibleRow()

            self.profile.places.createSeparator(parentGUID: self.bookmarkFolderGUID,
                                                position: UInt32(centerVisibleRow)) >>== { guid in
                self.profile.places.getBookmark(guid: guid).uponQueue(.main) { result in
                    guard let bookmarkNode = result.successValue, let bookmarkSeparator = bookmarkNode as? BookmarkSeparatorData else {
                        return
                    }

                    let indexPath = IndexPath(row: centerVisibleRow, section: BookmarksSection.bookmarks.rawValue)
                    self.tableView.beginUpdates()
                    self.bookmarkNodes.insert(bookmarkSeparator, at: centerVisibleRow)
                    self.tableView.insertRows(at: [indexPath], with: .automatic)
                    self.tableView.endUpdates()

                    self.flashRow(at: indexPath)
                }
            }
        }).items

        let viewModel = PhotonActionSheetViewModel(actions: [[newBookmark, newFolder, newSeparator]],
                                                   modalStyle: .overFullScreen)
        let sheet = PhotonActionSheet(viewModel: viewModel)
        sheet.modalTransitionStyle = .crossDissolve
        present(sheet, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        if tableView.isEditing {
            disableEditMode()
        }
        super.viewWillTransition(to: size, with: coordinator)
    }

    override func applyTheme() {
        super.applyTheme()

        if let current = navigationController?.visibleViewController as? NotificationThemeable, current !== self {
            current.applyTheme()
        }
    }

    override func reloadData() {
        // Can be called while app backgrounded and the db closed, don't try to reload the data source in this case
        if profile.isShutdown { return }

        if bookmarkFolderGUID == BookmarkRoots.RootGUID {
            setupRootFolderData()
        } else if bookmarkFolderGUID == LocalDesktopFolder.localDesktopFolderGuid {
            setupLocalDesktopFolderData()
        } else {
            setupSubfolderData()
        }
    }

    private func setupRootFolderData() {
        profile.places.getBookmarksTree(rootGUID: BookmarkRoots.MobileFolderGUID, recursive: false).uponQueue(.main) { result in
            guard let folder = result.successValue as? BookmarkFolderData else {
                // TODO: Handle error case?
                self.bookmarkFolder = nil
                self.bookmarkNodes = []
                return
            }

            self.bookmarkFolder = folder
            self.bookmarkNodes = folder.children ?? []

            let desktopFolder = LocalDesktopFolder()
            self.bookmarkNodes.insert(desktopFolder, at: 0)

            self.tableView.reloadData()

            if self.flashLastRowOnNextReload {
                self.flashLastRowOnNextReload = false

                let lastIndexPath = IndexPath(row: self.bookmarkNodes.count - 1, section: BookmarksSection.bookmarks.rawValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + UX.RowFlashDelay) {
                    self.flashRow(at: lastIndexPath)
                }
            }
        }
    }

    // TODO: Laurie - put this elsewhere
    private var unfiledBookmarks: BookmarkNodeData?
    private var menuBookmarks: BookmarkNodeData?
    private var toolbarBookmarks: BookmarkNodeData?

    private func setupLocalDesktopFolderData() {
        let group = DispatchGroup()
        group.enter()
        profile.places.getBookmarksTree(rootGUID: BookmarkRoots.UnfiledFolderGUID, recursive: false).uponQueue(.main) { result in
            guard let folder = result.successValue as? BookmarkFolderData else {
                group.leave()
                return
            }
            self.unfiledBookmarks = folder
            group.leave()
        }

        group.enter()
        profile.places.getBookmarksTree(rootGUID: BookmarkRoots.MenuFolderGUID, recursive: false).uponQueue(.main) { result in
            guard let folder = result.successValue as? BookmarkFolderData else {
                group.leave()
                return
            }
            self.menuBookmarks = folder
            group.leave()
        }

        group.enter()
        profile.places.getBookmarksTree(rootGUID: BookmarkRoots.ToolbarFolderGUID, recursive: false).uponQueue(.main) { result in
            guard let folder = result.successValue as? BookmarkFolderData else {
                group.leave()
                return
            }
            self.toolbarBookmarks = folder
            group.leave()
        }

        group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
            // TODO: Laurie - I need a way to retrieve the parent folder?
            // Do I have the parent directly on the node data?
            self.bookmarkFolder = nil

            var temp = [BookmarkNodeData]()
            if let bookmarks = self.unfiledBookmarks {
                temp.append(bookmarks)
            }

            if let bookmarks = self.menuBookmarks {
                temp.append(bookmarks)
            }

            if let bookmarks = self.toolbarBookmarks {
                temp.append(bookmarks)
            }

            self.bookmarkNodes = temp
            self.tableView.reloadData()

            if self.flashLastRowOnNextReload {
                self.flashLastRowOnNextReload = false

                let lastIndexPath = IndexPath(row: self.bookmarkNodes.count - 1, section: BookmarksSection.bookmarks.rawValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + UX.RowFlashDelay) {
                    self.flashRow(at: lastIndexPath)
                }
            }
        }
    }

    private func setupSubfolderData() {
        profile.places.getBookmarksTree(rootGUID: bookmarkFolderGUID, recursive: false).uponQueue(.main) { result in
            guard let folder = result.successValue as? BookmarkFolderData else {
                // TODO: Handle error case?
                self.bookmarkFolder = nil
                self.bookmarkNodes = []
                return
            }

            self.bookmarkFolder = folder
            self.bookmarkNodes = folder.children ?? []

            self.tableView.reloadData()

            if self.flashLastRowOnNextReload {
                self.flashLastRowOnNextReload = false

                let lastIndexPath = IndexPath(row: self.bookmarkNodes.count - 1, section: BookmarksSection.bookmarks.rawValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + UX.RowFlashDelay) {
                    self.flashRow(at: lastIndexPath)
                }
            }
        }

    }

    func enableEditMode() {
        self.tableView.setEditing(true, animated: true)
    }

    func disableEditMode() {
        self.tableView.setEditing(false, animated: true)
    }

    fileprivate func backButtonView() -> UIView? {
        let navigationBarContentView = navigationController?.navigationBar.subviews.find({ $0.description.starts(with: "<_UINavigationBarContentView:") })
        return navigationBarContentView?.subviews.find({ $0.description.starts(with: "<_UIButtonBarButton:") })
    }

    fileprivate func centerVisibleRow() -> Int {
        let visibleCells = tableView.visibleCells
        if let middleCell = visibleCells[safe: visibleCells.count / 2],
           let middleIndexPath = tableView.indexPath(for: middleCell) {
            return middleIndexPath.row
        }

        return bookmarkNodes.count
    }

    fileprivate func deleteBookmarkNodeAtIndexPath(_ indexPath: IndexPath) {
        guard let bookmarkNode = bookmarkNodes[safe: indexPath.row]else {
            return
        }

        func doDelete() {
            // Perform the delete asynchronously even though we update the
            // table view data source immediately for responsiveness.
            _ = profile.places.deleteBookmarkNode(guid: bookmarkNode.guid)

            tableView.beginUpdates()
            bookmarkNodes.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .left)
            tableView.endUpdates()
            removeBookmarkShortcut()
        }

        // If this node is a folder and it is not empty, we need
        // to prompt the user before deleting.
        if let bookmarkFolder = bookmarkNode as? BookmarkFolderData,
           !bookmarkFolder.childGUIDs.isEmpty {
            let alertController = UIAlertController(title: .BookmarksDeleteFolderWarningTitle,
                                                    message: .BookmarksDeleteFolderWarningDescription,
                                                    preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: .BookmarksDeleteFolderCancelButtonLabel,
                                                    style: .cancel))
            alertController.addAction(UIAlertAction(title: .BookmarksDeleteFolderDeleteButtonLabel,
                                                    style: .destructive) { (action) in
                doDelete()
            })
            present(alertController, animated: true, completion: nil)
            return
        }

        doDelete()
    }

    fileprivate func indexPathIsValid(_ indexPath: IndexPath) -> Bool {
        return indexPath.section < numberOfSections(in: tableView) &&
        indexPath.row < tableView(tableView, numberOfRowsInSection: indexPath.section)
    }

    fileprivate func flashRow(at indexPath: IndexPath) {
        guard indexPathIsValid(indexPath) else {
            return
        }

        tableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle)

        DispatchQueue.main.asyncAfter(deadline: .now() + UX.RowFlashDelay) {
            if self.indexPathIsValid(indexPath) {
                self.tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }

    func didAddBookmarkNode() {
        flashLastRowOnNextReload = true
    }

    @objc fileprivate func didLongPressTableView(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        let touchPoint = longPressGestureRecognizer.location(in: tableView)
        guard longPressGestureRecognizer.state == .began,
              let indexPath = tableView.indexPathForRow(at: touchPoint) else {
                  return
              }

        presentContextMenu(for: indexPath)
    }

    @objc fileprivate func didLongPressBackButtonView(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        navigationController?.popToRootViewController(animated: true)
    }

    // MARK: UITableViewDataSource | UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let node = bookmarkNodes[safe: indexPath.row]

        guard let bookmarkNode = node else {
            return
        }

        guard !tableView.isEditing else {
            TelemetryWrapper.recordEvent(category: .action, method: .change, object: .bookmark, value: .bookmarksPanel)
            if let bookmarkFolder = self.bookmarkFolder, !(bookmarkNode is BookmarkSeparatorData) {
                let detailController = BookmarkDetailPanel(profile: profile, bookmarkNode: bookmarkNode,
                                                           parentBookmarkFolder: bookmarkFolder)
                navigationController?.pushViewController(detailController, animated: true)
            }
            return
        }

        // TODO: Laurie - Same, needs protocol so we dont have to use switch
        switch bookmarkNode {
        case let bookmarkFolder as BookmarkFolderData:
            let nextController = BookmarksPanel(profile: profile, bookmarkFolderGUID: bookmarkFolder.guid)
            if bookmarkFolder.isRoot, let localizedString = LocalizedRootBookmarkFolderStrings[bookmarkFolder.guid] {
                nextController.title = localizedString
            } else {
                nextController.title = bookmarkFolder.title
            }
            nextController.libraryPanelDelegate = libraryPanelDelegate
            navigationController?.pushViewController(nextController, animated: true)
        case let bookmarkItem as BookmarkItemData:
            libraryPanelDelegate?.libraryPanel(didSelectURLString: bookmarkItem.url, visitType: .bookmark)
            TelemetryWrapper.recordEvent(category: .action, method: .open, object: .bookmark, value: .bookmarksPanel)
        case let bookmarkFolder as LocalDesktopFolder:
            let nextController = BookmarksPanel(profile: profile, bookmarkFolderGUID: bookmarkFolder.guid)
            if let localizedString = LocalizedRootBookmarkFolderStrings[bookmarkFolder.guid] {
                nextController.title = localizedString
            }
            nextController.libraryPanelDelegate = libraryPanelDelegate
            navigationController?.pushViewController(nextController, animated: true)
        default:
            return // Likely a separator was selected so do nothing.
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return bookmarkNodes.count
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        if let folder = bookmarkFolder, folder.guid == BookmarkRoots.RootGUID {
            return 2
        }

        return 1
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let bookmarkNode = bookmarkNodes[safe: indexPath.row],
              let cell = tableView.dequeueReusableCell(withIdentifier: OneLineTableViewCell.cellIdentifier,
                                                       for: indexPath) as? OneLineTableViewCell
        else {
            return super.tableView(tableView, cellForRowAt: indexPath)
        }

        // TODO: Laurie - create configure method for those cell, with protocol so we dont have to unwrap cases
        switch bookmarkNode {
        case let bookmarkFolder as BookmarkFolderData:
            if bookmarkFolder.isRoot, let localizedString = LocalizedRootBookmarkFolderStrings[bookmarkFolder.guid] {
                cell.titleLabel.text = localizedString
            } else {
                cell.titleLabel.text = bookmarkFolder.title
            }

            cell.leftImageView.image = LegacyThemeManager.instance.currentName == .dark ? bookmarkFolderIconDark : bookmarkFolderIconNormal
            cell.leftImageView.contentMode = .center
            let imageView = UIImageView(image: chevronImage)
            cell.accessoryView = imageView
            cell.editingAccessoryType = .disclosureIndicator
            return cell

        case let bookmarkItem as BookmarkItemData:
            if bookmarkItem.title.isEmpty {
                cell.titleLabel.text = bookmarkItem.url
            } else {
                cell.titleLabel.text = bookmarkItem.title
            }

            cell.leftImageView.image = nil

            let site = Site(url: bookmarkItem.url, title: bookmarkItem.title, bookmarked: true, guid: bookmarkItem.guid)
            profile.favicons.getFaviconImage(forSite: site).uponQueue(.main) { result in
                // Check that we successfully retrieved an image (should always happen)
                // and ensure that the cell we were fetching for is still on-screen.
                guard let image = result.successValue else { return }

                cell.leftImageView.image = image
                cell.leftImageView.contentMode = .scaleAspectFill
                cell.setNeedsLayout()
            }

            cell.accessoryView = nil
            cell.editingAccessoryType = .disclosureIndicator
            return cell

        case is BookmarkSeparatorData:
            let cell = tableView.dequeueReusableCell(withIdentifier: SeparatorTableViewCell.cellIdentifier,
                                                     for: indexPath)
            return cell

        case let bookmarkFolder as LocalDesktopFolder:
            if let localizedString = LocalizedRootBookmarkFolderStrings[bookmarkFolder.guid] {
                cell.titleLabel.text = localizedString
            }

            cell.leftImageView.image = LegacyThemeManager.instance.currentName == .dark ? bookmarkFolderIconDark : bookmarkFolderIconNormal
            cell.leftImageView.contentMode = .center
            let imageView = UIImageView(image: chevronImage)
            cell.accessoryView = imageView
            cell.editingAccessoryType = .disclosureIndicator
            return cell

        default:
            return super.tableView(tableView, cellForRowAt: indexPath) // Should not happen.
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Root folders cannot be edited.
        guard let bookmarkFolder = self.bookmarkFolder, bookmarkFolder.guid != BookmarkRoots.RootGUID else {
            return false
        }

        return true
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Root folders cannot be moved.
        guard let bookmarkFolder = self.bookmarkFolder, bookmarkFolder.guid != BookmarkRoots.RootGUID else {
            return false
        }

        return true
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard let bookmarkNode = bookmarkNodes[safe: sourceIndexPath.row] else {
            return
        }

        _ = profile.places.updateBookmarkNode(guid: bookmarkNode.guid, position: UInt32(destinationIndexPath.row))

        bookmarkNodes.remove(at: sourceIndexPath.row)
        bookmarkNodes.insert(bookmarkNode, at: destinationIndexPath.row)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive,
                                              title: .BookmarksPanelDeleteTableAction) { [weak self] (_, _, completion) in
            guard let strongSelf = self else { completion(false); return }

            strongSelf.deleteBookmarkNodeAtIndexPath(indexPath)
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .delete,
                                         object: .bookmark,
                                         value: .bookmarksPanel,
                                         extras: ["gesture": "swipe"])
            completion(true)
        }

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: LibraryPanelContextMenu

extension BookmarksPanel: LibraryPanelContextMenu {
    func presentContextMenu(for site: Site,
                            with indexPath: IndexPath,
                            completionHandler: @escaping () -> PhotonActionSheet?) {
        guard let contextMenu = completionHandler() else {
            return
        }

        present(contextMenu, animated: true, completion: nil)
    }

    func getSiteDetails(for indexPath: IndexPath) -> Site? {
        guard let bookmarkNode = bookmarkNodes[safe: indexPath.row],
              let bookmarkItem = bookmarkNode as? BookmarkItemData
        else {
            return nil
        }

        return Site(url: bookmarkItem.url, title: bookmarkItem.title, bookmarked: true, guid: bookmarkItem.guid)
    }

    func getContextMenuActions(for site: Site, with indexPath: IndexPath) -> [PhotonRowActions]? {
        guard var actions = getDefaultContextMenuActions(for: site, libraryPanelDelegate: libraryPanelDelegate) else {
            return nil
        }

        let pinTopSite = SingleActionViewModel(title: .AddToShortcutsActionTitle,
                                               iconString: ImageIdentifiers.addShortcut,
                                               tapHandler: { _ in
            self.profile.history.addPinnedTopSite(site).uponQueue(.main) { result in
                if result.isSuccess {
                    SimpleToast().showAlertWithText(.AppMenu.AddPinToShortcutsConfirmMessage,
                                                    bottomContainer: self.view)
                }
            }
        }).items
        actions.append(pinTopSite)

        let removeAction = SingleActionViewModel(title: .RemoveBookmarkContextMenuTitle,
                                                 iconString: ImageIdentifiers.actionRemoveBookmark,
                                                 tapHandler: { _ in
            self.deleteBookmarkNodeAtIndexPath(indexPath)
            TelemetryWrapper.recordEvent(category: .action,
                                         method: .delete,
                                         object: .bookmark,
                                         value: .bookmarksPanel,
                                         extras: ["gesture": "long-press"])
        }).items
        actions.append(removeAction)

        return actions
    }
}

extension BookmarksPanel: Notifiable {

    func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case .FirefoxAccountChanged:
            reloadData()
        default:
            log.warning("Received unexpected notification \(notification.name)")
            break
        }
    }
}
