import AppKit
import Darwin
import XCTest
@testable import Search

@MainActor
final class TabSelectionTests: XCTestCase {
    private var browser: Browser!
    private var previousGroups = false
    private var previousSplit = false

    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-selection-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
        previousGroups = browser.prefs.usesTabGroups
        previousSplit = browser.prefs.splitView
        browser.prefs.usesTabGroups = false
        browser.prefs.splitView = false
    }

    override func tearDown() async throws {
        browser.prefs.usesTabGroups = previousGroups
        browser.prefs.splitView = previousSplit
        for tab in browser.tabs { tab.close() }
        browser = nil
        try await super.tearDown()
    }

    func testCommandClickAddsAndRemovesWithoutSwitchingThePage() throws {
        let active = try XCTUnwrap(browser.active)
        let other = appendTab()

        browser.selectForBulkAction(other, modifiers: .command)
        XCTAssertEqual(Set(browser.selectedTabs.map(\.id)), Set([active.id, other.id]))
        XCTAssertEqual(browser.activeID, active.id)

        browser.selectForBulkAction(other, modifiers: .command)
        XCTAssertEqual(browser.selectedTabs.map(\.id), [active.id])
        XCTAssertEqual(browser.activeID, active.id)
    }

    func testCommandClickOnTheCurrentTabStartsASelection() throws {
        let active = try XCTUnwrap(browser.active)

        browser.selectForBulkAction(active, modifiers: .command)

        XCTAssertEqual(browser.selectedTabs.map(\.id), [active.id])
        XCTAssertEqual(browser.activeID, active.id)
    }

    func testShiftClickSelectsTheRangeAndAPlainTabChangeClearsIt() throws {
        let first = try XCTUnwrap(browser.active)
        let second = appendTab()
        let third = appendTab()

        browser.selectForBulkAction(third, modifiers: .shift)
        XCTAssertEqual(Set(browser.selectedTabs.map(\.id)), Set([first.id, second.id, third.id]))
        XCTAssertEqual(browser.activeID, first.id)

        browser.select(second)
        XCTAssertTrue(browser.selectedTabs.isEmpty)
    }

    func testSelectingEitherSplitHalfSelectsThePairAsOneItem() throws {
        let first = try XCTUnwrap(browser.active)
        let second = appendTab()
        browser.prefs.splitView = true
        browser.pair(second, with: first, onLeft: false)

        browser.selectForBulkAction(first, modifiers: .command)

        XCTAssertEqual(Set(browser.selectedTabs.map(\.id)), Set([first.id, second.id]))
        XCTAssertTrue(browser.isTabSelected(first))
        XCTAssertTrue(browser.isTabSelected(second))
    }

    private func appendTab() -> Tab {
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        browser.insert(tab, at: browser.tabs.count)
        return tab
    }
}
