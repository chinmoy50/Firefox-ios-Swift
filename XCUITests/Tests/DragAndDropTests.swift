/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import XCTest

let firstWebsite = (url: Base.helper.path(forTestPage: "test-mozilla-org.html"), tabName: "Internet for people, not profit — Mozilla")
let secondWebsite = (url: Base.helper.path(forTestPage: "test-mozilla-book.html"), tabName: "The Book of Mozilla")
let exampleWebsite = (url: Base.helper.path(forTestPage: "test-example.html"), tabName: "Example Domain")
let homeTabName = "Home"
let websiteWithSearchField = "https://developer.mozilla.org/en-US/"

let exampleDomainTitle = "Example Domain"
let twitterTitle = "Twitter"


class DragAndDropTests: BaseTestCase {

    override func tearDown() {
        XCUIDevice.shared.orientation = UIDeviceOrientation.portrait
        super.tearDown()
    }

    // // Smoketest
    func testRearrangeTabsTabTray() {
        openTwoWebsites()
        navigator.goto(TabTray)
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)
        dragAndDrop(dragElement: Base.app.collectionViews.cells[firstWebsite.tabName], dropOnElement: Base.app.collectionViews.cells[secondWebsite.tabName])
        Base.helper.waitForExistence(Base.app.collectionViews.cells["Internet for people, not profit — Mozilla"], timeout: 10)
        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName, secondTab: firstWebsite.tabName)
    }

    func testRearrangeMoreThan3TabsTabTray() {
        // Arranging more than 3 to check that it works moving tabs between lines
        let thirdWebsite = (url: "example.com", tabName: "Example Domain")

        // Open three websites and home tab
        openTwoWebsites()
        navigator.goto(TabTray)
        navigator.performAction(Action.OpenNewTabFromTabTray)
        if Base.helper.iPad() {
            Base.helper.waitForExistence(Base.app.buttons["TopTabsViewController.tabsButton"])
        } else {
            Base.helper.waitForExistence(Base.app.buttons["TabToolbar.tabsButton"], timeout: 10)
        }
        navigator.openNewURL(urlString: thirdWebsite.url)
        Base.helper.waitUntilPageLoad()
        Base.helper.waitForTabsButton()
        navigator.goto(TabTray)

        let fourthWebsitePosition = Base.app.collectionViews.cells.element(boundBy: 3).label
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)
        XCTAssertEqual(fourthWebsitePosition, thirdWebsite.tabName, "last tab before is not correct")

        dragAndDrop(dragElement: Base.app.collectionViews.cells[firstWebsite.tabName], dropOnElement: Base.app.collectionViews.cells[thirdWebsite.tabName])

        let thirdWebsitePosition = Base.app.collectionViews.cells.element(boundBy: 2).label
        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName , secondTab: homeTabName)
        XCTAssertEqual(thirdWebsitePosition, thirdWebsite.tabName, "last tab after is not correct")
    }

    func testRearrangeTabsTabTrayLandscape() {
        // Set the device in landscape mode
        XCUIDevice.shared.orientation = UIDeviceOrientation.landscapeLeft
        openTwoWebsites()
        navigator.goto(TabTray)
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)

        // Rearrange the tabs via drag home tab and drop it on twitter tab
        dragAndDrop(dragElement: Base.app.collectionViews.cells[firstWebsite.tabName], dropOnElement: Base.app.collectionViews.cells[secondWebsite.tabName])

        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName, secondTab: firstWebsite.tabName)
    }

    func testDragAndDropHomeTabTabsTray() {
        navigator.openNewURL(urlString: secondWebsite.url)
        Base.helper.waitUntilPageLoad()
        Base.helper.waitForTabsButton()
        navigator.goto(TabTray)
        checkTabsOrder(dragAndDropTab: false, firstTab: homeTabName, secondTab: secondWebsite.tabName)

        // Drag and drop home tab from the first position to the second
        dragAndDrop(dragElement: Base.app.collectionViews.cells["Home"], dropOnElement: Base.app.collectionViews.cells[secondWebsite.tabName])

        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName , secondTab: homeTabName)
    }

    func testRearrangeTabsPrivateModeTabTray() {
        navigator.toggleOn(userState.isPrivate, withAction: Action.TogglePrivateMode)
        openTwoWebsites()
        navigator.goto(TabTray)
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)
        // Drag first tab on the second one
        dragAndDrop(dragElement: Base.app.collectionViews.cells[firstWebsite.tabName], dropOnElement: Base.app.collectionViews.cells[secondWebsite.tabName])

        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName, secondTab: firstWebsite.tabName)
    }
}

fileprivate extension BaseTestCase {
    func openTwoWebsites() {
        // Open two tabs
        navigator.openURL(firstWebsite.url)
        Base.helper.waitForTabsButton()
        navigator.goto(TabTray)
        navigator.openURL(secondWebsite.url)
        Base.helper.waitUntilPageLoad()
        Base.helper.waitForTabsButton()
    }

    func dragAndDrop(dragElement: XCUIElement, dropOnElement: XCUIElement) {
        dragElement.press(forDuration: 2, thenDragTo: dropOnElement)
    }

    func checkTabsOrder(dragAndDropTab: Bool, firstTab: String, secondTab: String) {
        let firstTabCell = Base.app.collectionViews.cells.element(boundBy: 0).label
        let secondTabCell = Base.app.collectionViews.cells.element(boundBy: 1).label

        if (dragAndDropTab) {
            sleep(1)
            XCTAssertEqual(firstTabCell, firstTab, "first tab after is not correct")
            XCTAssertEqual(secondTabCell, secondTab, "second tab after is not correct")
        } else {
            XCTAssertEqual(firstTabCell, firstTab, "first tab before is not correct")
            XCTAssertEqual(secondTabCell, secondTab, "second tab before is not correct")
        }
    }
}

class DragAndDropTestIpad: IpadOnlyTestCase {

    let testWithDB = ["testTryDragAndDropHistoryToURLBar","testTryDragAndDropBookmarkToURLBar","testDragAndDropBookmarkEntry","testDragAndDropHistoryEntry"]

        // This DDBB contains those 4 websites listed in the name
    let historyAndBookmarksDB = "browserYoutubeTwitterMozillaExample.db"

    override func setUp() {
        // Test name looks like: "[Class testFunc]", parse out the function name
        let parts = name.replacingOccurrences(of: "]", with: "").split(separator: " ")
        let key = String(parts[1])
        if testWithDB.contains(key) {
            // for the current test name, add the db fixture used
                launchArguments = [LaunchArguments.SkipIntro, LaunchArguments.SkipWhatsNew, LaunchArguments.LoadDatabasePrefix + historyAndBookmarksDB]
        }
        super.setUp()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = UIDeviceOrientation.portrait
        super.tearDown()
    }

    func testRearrangeTabs() {
        if Base.helper.skipPlatform { return }

        openTwoWebsites()
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)
        // Drag first tab on the second one
        dragAndDrop(dragElement: Base.app.collectionViews.cells[firstWebsite.tabName], dropOnElement: Base.app.collectionViews.cells[secondWebsite.tabName])
        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName, secondTab: firstWebsite.tabName)
        // Check that focus is kept on last website open
        XCTAssert(secondWebsite.url.contains(Base.app.textFields["url"].value! as! String), "The tab has not been dropped correctly")
    }

    func testRearrangeTabsLandscape() {
        if Base.helper.skipPlatform { return }

        // Set the device in landscape mode
        XCUIDevice.shared.orientation = UIDeviceOrientation.landscapeLeft
        openTwoWebsites()
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)

        // Rearrange the tabs via drag home tab and drop it on twitter tab
        dragAndDrop(dragElement: Base.app.collectionViews.cells[firstWebsite.tabName], dropOnElement: Base.app.collectionViews.cells[secondWebsite.tabName])

        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName, secondTab: firstWebsite.tabName)
        // Check that focus is kept on last website open
        XCTAssert(secondWebsite.url.contains(Base.app.textFields["url"].value! as! String), "The tab has not been dropped correctly")
    }
    /*Disabled due to 5561
    func testDragDropToInvalidArea() {
        if Base.helper.skipPlatform { return }

        openTwoWebsites()
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)
        // Rearrange the tabs via drag home tab and drop it to the tabs button
        dragAndDrop(dragElement: Base.app.collectionViews.cells[firstWebsite.tabName], dropOnElement: Base.app.buttons["TopTabsViewController.tabsButton"])

        // Check that the order of the tabs have not changed
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)
        // Check that focus on the website does not change either
        XCTAssert(secondWebsite.url.contains(Base.app.textFields["url"].value! as! String), "The tab has not been dropped correctly")
    }*/

    func testDragAndDropHomeTab() {
        if Base.helper.skipPlatform { return }

        // Home tab is open and then a new website
        navigator.openNewURL(urlString: secondWebsite.url)
        Base.helper.waitUntilPageLoad()
        checkTabsOrder(dragAndDropTab: false, firstTab: homeTabName, secondTab: secondWebsite.tabName)
        Base.helper.waitForExistence(Base.app.collectionViews.cells.element(boundBy: 1))

        // Drag and drop home tab from the second position to the first one
        dragAndDrop(dragElement: Base.app.collectionViews.cells["Home"], dropOnElement: Base.app.collectionViews.cells[secondWebsite.tabName])

        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName , secondTab: homeTabName)
        // Check that focus is kept on last website open
        XCTAssert(secondWebsite.url.contains(Base.app.textFields["url"].value! as! String), "The tab has not been dropped correctly")
    }

    func testRearrangeTabsPrivateMode() {
        if Base.helper.skipPlatform { return }

        navigator.toggleOn(userState.isPrivate, withAction: Action.TogglePrivateMode)
        openTwoWebsites()
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)
        // Drag first tab on the second one
        dragAndDrop(dragElement: Base.app.collectionViews.cells[firstWebsite.tabName], dropOnElement: Base.app.collectionViews.cells[secondWebsite.tabName])

        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName, secondTab: firstWebsite.tabName)
        // Check that focus is kept on last website open
        XCTAssert(secondWebsite.url.contains(Base.app.textFields["url"].value! as! String), "The tab has not been dropped correctly")
    }
        
    func testRearrangeTabsTabTrayIsKeptinTopTabs() {
        if Base.helper.skipPlatform { return }
        openTwoWebsites()
        checkTabsOrder(dragAndDropTab: false, firstTab: firstWebsite.tabName, secondTab: secondWebsite.tabName)
        navigator.goto(TabTray)

        // Drag first tab on the second one
        dragAndDrop(dragElement: Base.app.collectionViews.cells[firstWebsite.tabName], dropOnElement: Base.app.collectionViews.cells[secondWebsite.tabName])
        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName, secondTab: firstWebsite.tabName)

        // Leave Tab Tray and check order in Top Tabs
        Base.app.collectionViews.cells[firstWebsite.tabName].tap()
        checkTabsOrder(dragAndDropTab: true, firstTab: secondWebsite.tabName, secondTab: firstWebsite.tabName)
    }

    // This test drags the address bar and since it is not possible to drop it on another app, lets do it in a search box
    /* Disable since the drag and drop is not working fine in this scenario on simulator
    func testDragAddressBarIntoSearchBox() {
        if Base.helper.skipPlatform { return }

        navigator.openURL("developer.mozilla.org/en-US")
        Base.helper.waitUntilPageLoad()
        // Check the text in the search field before dragging and dropping the url text field
        Base.helper.waitForValueContains(Base.app.webViews.searchFields.element(boundBy: 0), value: "Search")
        // DragAndDrop the url for only one second so that the TP menu is not shown and the search box is not covered
        Base.app.textFields["url"].press(forDuration: 1, thenDragTo: Base.app.webViews.searchFields.element(boundBy: 0))

        // Verify that the text in the search field is the same as the text in the url text field
        XCTAssertEqual(Base.app.webViews.searchFields.element(boundBy: 0).value as? String, websiteWithSearchField)
    }*/

    func testDragAndDropHistoryEntry() {
        if Base.helper.skipPlatform { return }

        // Drop a bookmark/history entry is only allowed on other apps. This test is to check that nothing happens within the app
        navigator.goto(BrowserTabMenu)
        navigator.goto(LibraryPanel_History)

        let firstEntryOnList = Base.app.tables["History List"].cells.element(boundBy:
            6).staticTexts[exampleDomainTitle]
        let secondEntryOnList = Base.app.tables["History List"].cells.element(boundBy: 3).staticTexts[twitterTitle]

        XCTAssertTrue(firstEntryOnList.exists, "first entry before is not correct")
        XCTAssertTrue(secondEntryOnList.exists, "second entry before is not correct")

        // Drag and Drop the element and check that the position of the two elements does not change
        Base.app.tables["History List"].cells.staticTexts[twitterTitle].press(forDuration: 1, thenDragTo: Base.app.tables["History List"].cells.staticTexts[exampleDomainTitle])

        XCTAssertTrue(firstEntryOnList.exists, "first entry after is not correct")
        XCTAssertTrue(secondEntryOnList.exists, "second entry after is not correct")
    }

    func testDragAndDropBookmarkEntry() {
        if Base.helper.skipPlatform { return }

        navigator.goto(MobileBookmarks)
        Base.helper.waitForExistence(Base.app.tables["Bookmarks List"])

        let firstEntryOnList = Base.app.tables["Bookmarks List"].cells.element(boundBy: 0).staticTexts[exampleDomainTitle]
        let secondEntryOnList = Base.app.tables["Bookmarks List"].cells.element(boundBy: 3).staticTexts[twitterTitle]

        XCTAssertTrue(firstEntryOnList.exists, "first entry after is not correct")
        XCTAssertTrue(secondEntryOnList.exists, "second entry after is not correct")

        // Drag and Drop the element and check that the position of the two elements does not change
        Base.app.tables["Bookmarks List"].cells.staticTexts[exampleDomainTitle].press(forDuration: 1, thenDragTo: Base.app.tables["Bookmarks List"].cells.staticTexts[twitterTitle])

        XCTAssertTrue(firstEntryOnList.exists, "first entry after is not correct")
        XCTAssertTrue(secondEntryOnList.exists, "second entry after is not correct")
    }

    // Test disabled due to new way bookmark panel is shown, url is not available. Library implementation bug 1506989
    // Will be removed if this is going the final implementation
    func testTryDragAndDropHistoryToURLBar() {
        if Base.helper.skipPlatform { return }

        navigator.goto(LibraryPanel_History)
        Base.helper.waitForExistence(Base.app.tables["History List"].cells.staticTexts[twitterTitle])

        Base.app.tables["History List"].cells.staticTexts[twitterTitle].press(forDuration: 1, thenDragTo: Base.app.textFields["url"])

        // It is not allowed to drop the entry on the url field
        let urlBarValue = Base.app.textFields["url"].value as? String
        XCTAssertEqual(urlBarValue, "Search or enter address")
    }

    // Test disabled due to new way bookmark panel is shown, url is not available. Library implementation bug 1506989
    // Will be removed if this is going the final implementation
    func testTryDragAndDropBookmarkToURLBar() {
        if Base.helper.skipPlatform { return }

        navigator.goto(MobileBookmarks)
        Base.helper.waitForExistence(Base.app.tables["Bookmarks List"])
        Base.app.tables["Bookmarks List"].cells.staticTexts[twitterTitle].press(forDuration: 1, thenDragTo: Base.app.textFields["url"])

        // It is not allowed to drop the entry on the url field
        let urlBarValue = Base.app.textFields["url"].value as? String
        XCTAssertEqual(urlBarValue, "Search or enter address")
    }
}
