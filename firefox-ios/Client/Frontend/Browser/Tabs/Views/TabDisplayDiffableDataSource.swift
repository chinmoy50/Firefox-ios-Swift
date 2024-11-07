// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

typealias TabDisplayViewSection = TabDisplayDiffableDataSource.TabSection
typealias TabDisplayViewItem = TabDisplayDiffableDataSource.TabItem

final class TabDisplayDiffableDataSource: UICollectionViewDiffableDataSource<TabDisplayViewSection, TabDisplayViewItem> {
    enum TabSection: Hashable {
        case inactiveTabs(UUID)
        case tabs
    }

    enum TabItem: Hashable {
        case inactiveTab(InactiveTabsModel)
        case tab(TabModel)
    }

    func updateSnapshot(state: TabsPanelState) {
        var snapshot = NSDiffableDataSourceSnapshot<TabDisplayViewSection, TabDisplayViewItem>()

        let inactiveTabsUUID = UUID()
        snapshot.appendSections([.inactiveTabs(inactiveTabsUUID), .tabs])

        if state.isInactiveTabsExpanded {
            let inactiveTabs = state.inactiveTabs.map { TabDisplayViewItem.inactiveTab($0) }
            snapshot.appendItems(inactiveTabs, toSection: .inactiveTabs(inactiveTabsUUID))
        }

        let tabs = state.tabs.map { TabDisplayViewItem.tab($0) }
        snapshot.appendItems(tabs, toSection: .tabs)

        apply(snapshot, animatingDifferences: true)
    }
}
