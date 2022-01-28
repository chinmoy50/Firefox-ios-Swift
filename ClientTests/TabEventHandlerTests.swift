// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
@testable import Client
import WebKit
import GCDWebServers
import XCTest
import Shared

class TabEventHandlerTests: XCTestCase {

    func testEventDelivery() {
        let tab = Tab(bvc: BrowserViewController.foregroundBVC(), configuration: WKWebViewConfiguration())
        let handler = DummyHandler()

        XCTAssertNil(handler.isFocused)

        TabEvent.post(.didGainFocus, for: tab)
        XCTAssertTrue(handler.isFocused!)

        TabEvent.post(.didLoseFocus, for: tab)
        XCTAssertFalse(handler.isFocused!)
    }


    func testBlankPopupURL() {
        let manager = BrowserViewController.foregroundBVC().tabManager
        let prefs = BrowserViewController.foregroundBVC().profile.prefs

        // Hide intro so it is easier to see the test running and debug it
        prefs.setInt(1, forKey: PrefsKeys.IntroSeen)
        prefs.setString(ETPCoverSheetShowType.DoNotShow.rawValue, forKey: PrefsKeys.KeyETPCoverSheetShowType)

        let webServer = GCDWebServer()
        webServer.addHandler(forMethod: "GET", path: "/blankpopup", request: GCDWebServerRequest.self) { (request) -> GCDWebServerResponse in
            let page = """
                <html>
                <body onload="window.open('')">open about:blank popup</body>
                </html>
            """
            return GCDWebServerDataResponse(html: page)!
        }

        if !webServer.start(withPort: 0, bonjourName: nil) {
            XCTFail("Can't start the GCDWebServer")
        }
        let webServerBase = "http://localhost:\(webServer.port)"

        prefs.setBool(false, forKey: PrefsKeys.KeyBlockPopups)
        manager.addTab(URLRequest(url: URL(string: "\(webServerBase)/blankpopup")!))

        XCTAssertEqual(manager.tabs.count, 2)
        let exists = NSPredicate() { obj, _ in
            let tabManager = obj as! TabManager
            return tabManager.tabs.count > 2
        }

        expectation(for: exists, evaluatedWith: manager) {
            var urlIsAboutBlank = false
            var urlsList = [String]()
            for tab in manager.tabs {
                guard let url = tab.url?.absoluteString else { continue }
                urlsList.append(url)
                if url == "about:blank" {
                    urlIsAboutBlank = true
                }
            }

            XCTAssertTrue(urlIsAboutBlank, "URLs should contain \"about:blank:\" - \(urlsList)")
            return true
        }

        waitForExpectations(timeout: 20, handler: nil)
    }
}


class DummyHandler: TabEventHandler {
    // This is not how this should be written in production — the handler shouldn't be keeping track
    // of individual tab state.
    var isFocused: Bool? = nil

    init() {
         register(self, forTabEvents: .didGainFocus, .didLoseFocus)
    }

    func tabDidGainFocus(_ tab: Tab) {
        isFocused = true
    }

    func tabDidLoseFocus(_ tab: Tab) {
        isFocused = false
    }
}
