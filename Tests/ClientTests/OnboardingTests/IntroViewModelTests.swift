// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest

@testable import Client

class IntroViewModelTests: XCTestCase {
    var nimbusUtility: NimbusOnboardingConfigUtility!
    typealias cards = NimbusOnboardingConfigUtility.CardOrder

    override func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        nimbusUtility = NimbusOnboardingConfigUtility()
    }

    override func tearDown() {
        super.tearDown()
        nimbusUtility = nil
    }

    func testModel_whenInitialized_hasNoViewControllers() {
        nimbusUtility.setupNimbus(withOrder: cards.welcomeNotificationsSync)
        let subject = createSubject()
        let expectedNumberOfViewControllers = 0

        XCTAssertEqual(subject.availableCards.count, expectedNumberOfViewControllers)
    }

    func testModel_whenInitializedWithAllCards_onlyReturnsOnboardingCards() {
        nimbusUtility.setupNimbus(withOrder: cards.allCards)
        let subject = createSubject()
        let expectedNumberOfViewControllers = 3

        subject.setupViewControllerDelegates(with: MockOnboardinCardDelegateController())

        XCTAssertEqual(subject.availableCards.count, expectedNumberOfViewControllers)
        XCTAssertEqual(subject.availableCards[0].viewModel.infoModel.name, cards.welcome)
        XCTAssertEqual(subject.availableCards[1].viewModel.infoModel.name, cards.notifications)
        XCTAssertEqual(subject.availableCards[2].viewModel.infoModel.name, cards.sync)
    }

    func testModel_hasThreeAvailableCards_inExpectedOrder() {
        nimbusUtility.setupNimbus(withOrder: cards.welcomeNotificationsSync)
        let subject = createSubject()
        let expectedNumberOfViewControllers = 3

        subject.setupViewControllerDelegates(with: MockOnboardinCardDelegateController())

        XCTAssertEqual(subject.availableCards.count, expectedNumberOfViewControllers)
        XCTAssertEqual(subject.availableCards[0].viewModel.infoModel.name, cards.welcome)
        XCTAssertEqual(subject.availableCards[1].viewModel.infoModel.name, cards.notifications)
        XCTAssertEqual(subject.availableCards[2].viewModel.infoModel.name, cards.sync)
    }

    func testModel_hasTwoAvailableCards_inExpectedOrder() {
        nimbusUtility.setupNimbus(withOrder: cards.welcomeSync)
        let subject = createSubject()
        let expectedNumberOfViewControllers = 2

        subject.setupViewControllerDelegates(with: MockOnboardinCardDelegateController())

        XCTAssertEqual(subject.availableCards.count, expectedNumberOfViewControllers)
        XCTAssertEqual(subject.availableCards[0].viewModel.infoModel.name, cards.welcome)
        XCTAssertEqual(subject.availableCards[1].viewModel.infoModel.name, cards.sync)
    }

    // MARK: - Test index moving forward
    func testIndexAfterFirstCard() {
        nimbusUtility.setupNimbus(withOrder: cards.welcomeNotificationsSync)
        let subject = createSubject()
        let expectedIndex = 1

        subject.setupViewControllerDelegates(with: MockOnboardinCardDelegateController())

        let resultIndex = subject.getNextIndex(currentIndex: 0, goForward: true)
        XCTAssertEqual(resultIndex, expectedIndex)
    }

    func testIndexAfterSecondCard() {
        nimbusUtility.setupNimbus(withOrder: cards.welcomeNotificationsSync)
        let subject = createSubject()
        let expectedIndex = 2

        subject.setupViewControllerDelegates(with: MockOnboardinCardDelegateController())

        let resultIndex = subject.getNextIndex(currentIndex: 1, goForward: true)
        XCTAssertEqual(resultIndex, expectedIndex)
    }

    func testNextIndexAfterLastCard() {
        nimbusUtility.setupNimbus(withOrder: cards.welcomeNotificationsSync)
        let subject = createSubject()

        subject.setupViewControllerDelegates(with: MockOnboardinCardDelegateController())

        let resultIndex = subject.getNextIndex(currentIndex: 2, goForward: true)
        XCTAssertNil(resultIndex)
    }

    // MARK: - Test index moving backwards
    func testIndexBeforeLastCard() {
        nimbusUtility.setupNimbus(withOrder: cards.welcomeNotificationsSync)
        let subject = createSubject()
        let expectedIndex = 1

        subject.setupViewControllerDelegates(with: MockOnboardinCardDelegateController())

        let resultIndex = subject.getNextIndex(currentIndex: 2, goForward: false)
        XCTAssertEqual(resultIndex, expectedIndex)
    }

    func testIndexBeforeSecondCard() {
        nimbusUtility.setupNimbus(withOrder: cards.welcomeNotificationsSync)
        let subject = createSubject()
        let expectedIndex = 0

        subject.setupViewControllerDelegates(with: MockOnboardinCardDelegateController())

        let resultIndex = subject.getNextIndex(currentIndex: 1, goForward: false)
        XCTAssertEqual(resultIndex, expectedIndex)
    }

    func testNextIndexBeforeFirstCard() {
        nimbusUtility.setupNimbus(withOrder: cards.welcomeNotificationsSync)
        let subject = createSubject()

        subject.setupViewControllerDelegates(with: MockOnboardinCardDelegateController())

        let resultIndex = subject.getNextIndex(currentIndex: 0, goForward: false)
        XCTAssertNil(resultIndex)
    }

    // MARK: - Private Helpers
    func createSubject() -> IntroViewModel {
        let subject = IntroViewModel(profile: MockProfile(databasePrefix: "introViewModelTests_"))

        trackForMemoryLeaks(subject)

        return subject
    }
}
