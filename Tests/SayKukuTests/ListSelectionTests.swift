import Testing
@testable import SayKuku

@Suite("List selection after delete")
struct ListSelectionTests {
    private struct Item: Identifiable {
        let id: Int
    }

    private let items = [Item(id: 1), Item(id: 2), Item(id: 3)]

    @Test("moves to the next item")
    func nextItem() {
        #expect(items.selectionAfterRemoving(1) == 2)
        #expect(items.selectionAfterRemoving(2) == 3)
    }

    @Test("moves to the previous item at the end")
    func previousItemAtEnd() {
        #expect(items.selectionAfterRemoving(3) == 2)
    }

    @Test("clears when nothing is left or the item isn't listed")
    func clears() {
        #expect([Item(id: 1)].selectionAfterRemoving(1) == nil)
        #expect(items.selectionAfterRemoving(9) == nil)
    }
}
