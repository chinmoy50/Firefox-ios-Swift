// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import ComponentLibrary
import Storage
@testable import Client

final class BottomSheetCardCoordinatorTests: XCTestCase {
    private var profile: MockProfile!
    private var router: MockRouter!
    private var parentCoordinator: MockBrowserCoordinator!

    override func setUp() {
        super.setUp()
        profile = MockProfile()
        router = MockRouter(navigationController: UINavigationController())
        parentCoordinator = MockBrowserCoordinator()
        DependencyHelperMock().bootstrapDependencies()
    }

    override func tearDown() {
        super.tearDown()
        profile = nil
        router = nil
        parentCoordinator = nil
        DependencyHelperMock().reset()
    }

    func testShowPassCodeController() {
        let subject = createSubject()

        subject.showPassCodeController()

        XCTAssertTrue(router.presentedViewController is DevicePasscodeRequiredViewController)
        XCTAssertEqual(router.presentCalled, 1)
    }

    func testShowBottomSheetCard() {
        let subject = createSubject()

        subject.showBottomSheetCardViewController(creditCard: nil, decryptedCard: nil, viewType: .save, frame: nil, alertContainer: UIView())

        XCTAssertTrue(router.presentedViewController is BottomSheetViewController)
        XCTAssertEqual(router.presentCalled, 1)
    }

    func testShowBottomSheetCard_didTapYesButton_callDidFinish() {
        let subject = createSubject()

        subject.showBottomSheetCardViewController(creditCard: nil, decryptedCard: nil, viewType: .save, frame: nil, alertContainer: UIView())

        if let bottomSheetViewController = router.presentedViewController as? BottomSheetViewController {
            bottomSheetViewController.loadViewIfNeeded()
            if let creditCardViewController = bottomSheetViewController.children.first(where: {  $0 is CreditCardBottomSheetViewController
            }) as? CreditCardBottomSheetViewController {
                creditCardViewController.didTapYesClosure?(nil)
                XCTAssertEqual(parentCoordinator.didFinishCalled, 1)
            } else {
                XCTFail("The BottomSheetViewController has to contains a CreditCardBottomSheetViewControler as child")
            }
        } else {
            XCTFail("A BottomSheetViewController has to be presented")
        }
    }

    func testShowBottomSheetCard_didTapCreditCardFill_callDidFinish() {
        let subject = createSubject()

        subject.showBottomSheetCardViewController(creditCard: nil, decryptedCard: nil, viewType: .save, frame: nil, alertContainer: UIView())

        if let bottomSheetViewController = router.presentedViewController as? BottomSheetViewController {
            bottomSheetViewController.loadViewIfNeeded()
            if let creditCardViewController = bottomSheetViewController.children.first(where: {  $0 is CreditCardBottomSheetViewController
            }) as? CreditCardBottomSheetViewController {
                creditCardViewController.didSelectCreditCardToFill?(UnencryptedCreditCardFields())
                XCTAssertEqual(parentCoordinator.didFinishCalled, 1)
            } else {
                XCTFail("The BottomSheetViewController has to contains a CreditCardBottomSheetViewControler as child")
            }
        } else {
            XCTFail("A BottomSheetViewController has to be presented")
        }
    }

    func testShowBottomSheetCard_didTapManageCards_callDidFinish() {
        let subject = createSubject()

        subject.showBottomSheetCardViewController(creditCard: nil, decryptedCard: nil, viewType: .save, frame: nil, alertContainer: UIView())

        if let bottomSheetViewController = router.presentedViewController as? BottomSheetViewController {
            bottomSheetViewController.loadViewIfNeeded()
            if let creditCardViewController = bottomSheetViewController.children.first(where: {  $0 is CreditCardBottomSheetViewController
            }) as? CreditCardBottomSheetViewController {
                creditCardViewController.didTapManageCardsClosure?()
                XCTAssertEqual(parentCoordinator.didFinishCalled, 1)
            } else {
                XCTFail("The BottomSheetViewController has to contains a CreditCardBottomSheetViewControler as child")
            }
        } else {
            XCTFail("A BottomSheetViewController has to be presented")
        }
    }

    private func createSubject() -> BottomSheetCardCoordinator {
        let subject = BottomSheetCardCoordinator(
            profile: profile,
            router: router,
            parentCoordinator: parentCoordinator
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
