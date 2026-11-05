import Foundation
import XCTest
import NotchShell

final class NotchNavigationTests: XCTestCase {
    func testClosePolicyMatrix() async {
        await MainActor.run {
            for reset in [false, true] {
                for items in [false, true] {
                    for opensShelf in [false, true] {
                        for keepsLast in [false, true] {
                            let navigation = NotchNavigation()
                            navigation.select(.goal)
                            navigation.close(resetSelection: reset, shelfHasItems: items,
                                             opensShelf: opensShelf, keepsLastTab: keepsLast)
                            let expected: NotchTab = !reset ? .goal : items && opensShelf ? .shelf : keepsLast ? .goal : .home
                            XCTAssertEqual(navigation.selection, expected)
                        }
                    }
                }
            }
        }
    }
    func testFocusTransferPreservesSharedTabRegardlessOfNativeCallbackOrder() async {
        await MainActor.run {
            for destinationBecomesKeyFirst in [false, true] {
                let navigation = NotchNavigation()
                let a = UUID(), b = UUID()
                navigation.register(a)
                navigation.register(b)
                navigation.select(.goal)
                navigation.requestEditor(true, on: a)
                navigation.becameKey(a)
                navigation.requestEditor(true, on: b)
                if destinationBecomesKeyFirst { navigation.becameKey(b) }
                let reset = navigation.resignedKey(a)
                navigation.close(resetSelection: reset, shelfHasItems: false, opensShelf: false, keepsLastTab: false)
                if !destinationBecomesKeyFirst { navigation.becameKey(b) }
                XCTAssertFalse(reset)
                XCTAssertEqual(navigation.selection, .goal)
                XCTAssertEqual(navigation.focusedEditor, b)
                XCTAssertTrue(navigation.resignedKey(b))
                XCTAssertNil(navigation.focusedEditor)
            }
        }
    }
    func testRemovedAndCanceledEditorsCannotKeepFocusOrBlockClose() async {
        await MainActor.run {
            let navigation = NotchNavigation()
            let a = UUID(), b = UUID()
            navigation.register(a)
            navigation.register(b)
            navigation.select(.goal)
            navigation.requestEditor(true, on: a)
            navigation.requestEditor(true, on: b)
            navigation.becameKey(b)
            navigation.remove(b)
            XCTAssertFalse(navigation.resignedKey(b), "removed native windows cannot reset the shared tab")
            navigation.requestEditor(true, on: b)
            navigation.becameKey(b)
            XCTAssertNil(navigation.focusedEditor)
            XCTAssertTrue(navigation.resignedKey(a))
            navigation.requestEditor(true, on: a)
            navigation.becameKey(a)
            navigation.select(.shelf)
            XCTAssertNil(navigation.focusedEditor)
            XCTAssertTrue(navigation.resignedKey(a))
        }
    }
}
