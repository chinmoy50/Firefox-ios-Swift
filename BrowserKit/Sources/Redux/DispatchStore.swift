// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Protocol that allows to subscribe to the store and receive dispatched actions to modify the store state
public protocol DispatchStore {
    func dispatch(_ action: Action)
}

public protocol DefaultDispatchStore: DispatchStore {
    associatedtype State

    var state: State { get }

    func subscribe<S: StoreSubscriber>(_ subscriber: S) where S.SubscriberStateType == State
    func unsubscribe<S: StoreSubscriber>(_ subscriber: S) where S.SubscriberStateType == State
}
