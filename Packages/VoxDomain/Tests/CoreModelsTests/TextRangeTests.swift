import CoreModels
import Foundation
import Testing

struct TextRangeTests {
    @Test(arguments: [(0, 0, 0), (0, 4, 4), (7, 0, 7), (7, 4, 11)])
    func endIsExclusive(location: Int, length: Int, expectedEnd: Int) {
        let range = TextRange(location: location, length: length)

        #expect(range.end == expectedEnd)
    }

    @Test(arguments: [(0, 0, true), (7, 0, true), (0, 4, false), (7, 4, false)])
    func isEmptyDependsOnLength(location: Int, length: Int, expectedIsEmpty: Bool) {
        let range = TextRange(location: location, length: length)

        #expect(range.isEmpty == expectedIsEmpty)
    }

    @Test(arguments: [(0, 0), (7, 0), (0, 4), (7, 4)])
    func nsRangeRoundTripPreservesLocationAndLength(location: Int, length: Int) {
        let original = NSRange(location: location, length: length)
        let range = TextRange(original)

        #expect(range.location == location)
        #expect(range.length == length)
        #expect(range.nsRange == original)
    }
}
