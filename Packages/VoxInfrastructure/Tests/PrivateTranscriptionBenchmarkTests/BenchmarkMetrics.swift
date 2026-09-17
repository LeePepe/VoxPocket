#if os(macOS)
import Foundation

struct BenchmarkScore: Codable, Equatable, Sendable {
    let cer: Double
    let mixedTokenErrorRate: Double
    let punctuationEdits: Int
    let punctuationReferenceCount: Int
    let preservesTest: Bool
}

enum BenchmarkScoring {
    /// NFKC、统一大小写；CER 去空白/标点；混合词元按汉字逐字、ASCII 单词整体计数。
    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
    }

    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var word = ""
        for ch in normalized(text) {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { word.append(ch); continue }
            if !word.isEmpty { result.append(word); word = "" }
            if ch.isLetter || ch.isNumber { result.append(String(ch)) }
        }
        if !word.isEmpty { result.append(word) }
        return result
    }

    static func distance<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, right) in rhs.enumerated() {
                next[j + 1] = min(next[j] + 1, previous[j + 1] + 1,
                                  previous[j] + (left == right ? 0 : 1))
            }
            previous = next
        }
        return previous[rhs.count]
    }

    static func score(reference: String, recognized: String) -> BenchmarkScore {
        let ref = Array(normalized(reference).filter { $0.isLetter || $0.isNumber })
        let hyp = Array(normalized(recognized).filter { $0.isLetter || $0.isNumber })
        let refWords = tokens(reference), hypWords = tokens(recognized)
        let refPunctuation = Array(normalized(reference).filter(\.isPunctuation))
        let hypPunctuation = Array(normalized(recognized).filter(\.isPunctuation))
        return BenchmarkScore(
            cer: Double(distance(ref, hyp)) / Double(max(ref.count, 1)),
            mixedTokenErrorRate: Double(distance(refWords, hypWords)) / Double(max(refWords.count, 1)),
            punctuationEdits: distance(refPunctuation, hypPunctuation),
            punctuationReferenceCount: refPunctuation.count,
            preservesTest: hypWords.contains("test")
        )
    }
}

struct BenchmarkRun: Codable, Sendable {
    let iteration: Int
    let cold: Bool
    var status = "ok"
    var firstPartialSeconds: Double?
    var inputSeconds: Double?
    var finalAfterInputSeconds: Double?
    var requestSeconds: Double?
    var totalSeconds: Double?
    var realTimeFactor: Double?
    var loadSeconds: Double?
    var preparationSeconds: Double?
    var mergeSeconds: Double?
    var refinementSeconds: Double?
    var mergeDisposition: String?
    var asrScore: BenchmarkScore?
    var mergedScore: BenchmarkScore?
    var score: BenchmarkScore?
}

struct BenchmarkSummary: Codable, Sendable {
    let provider: String
    let sourceSHA: String
    let dependencySHA: String
    let processID: Int32
    let generatedAt: Date
    let inputPacing: String
    let actualAppleRoute: String
    let cloudBackingModel: String
    let cachePresent: Bool
    let audioSeconds: Double
    let runs: [BenchmarkRun]
}

struct PrivateBenchmarkReport: Encodable {
    let summary: BenchmarkSummary
    let reference: String
    let recognized: [String]
    let merged: [String]
    let refined: [String]
    let normalization = "NFKC/lowercase; CER=letters+numbers; mixed=Han characters+ASCII words; punctuation=sequence edit count, position not scored"
}

func benchmarkNow() -> Double { ProcessInfo.processInfo.systemUptime }
#endif
