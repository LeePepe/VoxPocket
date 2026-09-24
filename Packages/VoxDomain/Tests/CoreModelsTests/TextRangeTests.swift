import CoreModels
import Foundation
import Testing

// MARK: - end

@Test("end 等于 location + length")
func textRangeEndIsLocationPlusLength() {
    #expect(TextRange(location: 3, length: 4).end == 7)
}

@Test("空范围的 end 等于 location")
func textRangeEndOfEmptyRangeEqualsLocation() {
    #expect(TextRange(location: 5, length: 0).end == 5)
    #expect(TextRange(location: 0, length: 0).end == 0)
}

// MARK: - isEmpty

@Test("length 为 0 时为空，与 location 无关")
func textRangeIsEmptyWhenLengthIsZero() {
    #expect(TextRange(location: 0, length: 0).isEmpty)
    #expect(TextRange(location: 5, length: 0).isEmpty)
}

@Test("length 大于 0 时不为空")
func textRangeIsNotEmptyWhenLengthIsPositive() {
    #expect(!TextRange(location: 0, length: 1).isEmpty)
    #expect(!TextRange(location: 4, length: 2).isEmpty)
}

// MARK: - NSRange 互转

@Test("从 NSRange 创建时复制 location 和 length")
func textRangeInitFromNSRangeCopiesFields() {
    let range = TextRange(NSRange(location: 2, length: 6))

    #expect(range.location == 2)
    #expect(range.length == 6)
    #expect(range.end == 8)
}

@Test("nsRange 与原范围一致")
func textRangeConvertsToNSRange() {
    #expect(TextRange(location: 2, length: 6).nsRange == NSRange(location: 2, length: 6))
}

@Test("TextRange → NSRange → TextRange 往返保持不变", arguments: [(0, 0), (1, 0), (0, 5), (7, 9)])
func textRangeRoundTripsThroughNSRange(location: Int, length: Int) {
    let original = TextRange(location: location, length: length)
    let roundTripped = TextRange(original.nsRange)

    #expect(roundTripped == original)
    #expect(roundTripped.end == location + length)
}

@Test("NSRange → TextRange → NSRange 往返保持不变")
func nsRangeRoundTripsThroughTextRange() {
    let nsRange = NSRange(location: 0, length: 12)

    #expect(TextRange(nsRange).nsRange == nsRange)
}
