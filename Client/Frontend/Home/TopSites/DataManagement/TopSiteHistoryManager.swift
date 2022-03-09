// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
import Shared

class TopSiteHistoryManager: DataObserver, Loggable {

    let profile: Profile
    weak var delegate: DataObserverDelegate?
    var notificationCenter = NotificationCenter.default

    private let ActivityStreamTopSiteCacheSize: Int32 = 32
    private let events: [Notification.Name] = [.FirefoxAccountChanged, .ProfileDidFinishSyncing, .PrivateDataClearedHistory]

    init(profile: Profile) {
        self.profile = profile
        self.profile.history.setTopSitesCacheSize(ActivityStreamTopSiteCacheSize)

        setupNotifications(forObserver: self, observing: events)
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    /// RefreshIfNeeded will refresh the underlying caches for TopSites.
    /// By default this will only refresh topSites if KeyTopSitesCacheIsValid is false
    /// - Parameter forceTopSites: Refresh can be forced by setting this to true
    func refreshIfNeeded(forceTopSites: Bool) {
        guard !profile.isShutdown else {
            return
        }

        // KeyTopSitesCacheIsValid is false when we want to invalidate. Thats why this logic is so backwards
        let shouldInvalidateTopSites = forceTopSites || !(profile.prefs.boolForKey(PrefsKeys.KeyTopSitesCacheIsValid) ?? false)
        guard shouldInvalidateTopSites else { return }

        // Flip the `KeyTopSitesCacheIsValid` flag now to prevent subsequent calls to refresh
        // from re-invalidating the cache.
        self.profile.prefs.setBool(true, forKey: PrefsKeys.KeyTopSitesCacheIsValid)

        self.delegate?.willInvalidateDataSources(forceTopSites: forceTopSites)
        // TODO: Laurie - .main necessary?
        self.profile.recommendations.repopulate(invalidateTopSites: shouldInvalidateTopSites).uponQueue(.main) { _ in
            self.delegate?.didInvalidateDataSources(refresh: forceTopSites, topSitesRefreshed: shouldInvalidateTopSites)
        }
    }
}

// MARK: - Notifiable protocol
extension TopSiteHistoryManager: Notifiable {
    func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case .ProfileDidFinishSyncing, .FirefoxAccountChanged, .PrivateDataClearedHistory:
             refreshIfNeeded(forceTopSites: true)
        default:
            browserLog.warning("Received unexpected notification \(notification.name)")
        }
    }
}
