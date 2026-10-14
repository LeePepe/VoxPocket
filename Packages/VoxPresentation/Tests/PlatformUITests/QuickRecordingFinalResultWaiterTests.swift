#if os(macOS)
import Combine
import Foundation
import Synchronization
import TranscriptionKit
import XCTest
@testable import PlatformUI

@MainActor
final class QuickRecordingFinalResultWaiterTests: XCTestCase {
    func testSubscriptionCapturesSynchronousFinalBeforeWaitTaskRuns() async {
        let subject = PassthroughSubject<TranscriptionResult, Error>()
        let waiter = QuickRecordingFinalResultWaiter(publisher: subject.eraseToAnyPublisher())
        subject.send(result("终稿"))
        XCTAssertEqual(waiter.capturedText, "终稿")
        await assertResult("终稿", from: waiter)
    }

    func testSynchronousPublisherCompletionReleasesInstalledSubscription() async {
        let waiter = QuickRecordingFinalResultWaiter(publisher: Just(result("终稿")).setFailureType(to: Error.self).eraseToAnyPublisher())
        XCTAssertEqual(waiter.capturedText, "终稿")
        await assertResult("终稿", from: waiter)
    }

    func testBackgroundPublisherDeliversFinalWithoutMainActorAssertion() async {
        let source = BackgroundSource()
        let waiter = QuickRecordingFinalResultWaiter(publisher: source.publisher)
        let final = result("后台终稿")
        await Task.detached { source.send(final) }.value
        XCTAssertEqual(waiter.capturedText, "后台终稿")
        await assertResult("后台终稿", from: waiter)
    }

    func testBackgroundPublisherCompletionAndFailureEndWithoutMainActorAssertion() async {
        for fails in [false, true] {
            let source = BackgroundSource()
            let waiter = QuickRecordingFinalResultWaiter(publisher: source.publisher)
            await Task.detached { source.complete(fails: fails) }.value
            await assertResult(nil, from: waiter)
        }
    }

    func testEmptyFinalEndsWaitingWithoutTimeout() async {
        let subject = PassthroughSubject<TranscriptionResult, Error>()
        let waiter = QuickRecordingFinalResultWaiter(publisher: subject.eraseToAnyPublisher())
        subject.send(result(" \n\t"))
        XCTAssertEqual(waiter.capturedText, "")
        await assertResult(nil, from: waiter)
    }

    func testPublisherCompletionAndFailureEndWaiting() async {
        for fails in [false, true] {
            let subject = PassthroughSubject<TranscriptionResult, Error>()
            let waiter = QuickRecordingFinalResultWaiter(publisher: subject.eraseToAnyPublisher())
            subject.send(completion: fails ? .failure(CancellationError()) : .finished)
            await assertResult(nil, from: waiter)
        }
    }

    func testTimeoutReleasesNeverCompletingPublisherSubscription() async {
        let subject = PassthroughSubject<TranscriptionResult, Error>()
        let cancellations = Counter()
        let publisher = subject.handleEvents(receiveCancel: { cancellations.increment() }).eraseToAnyPublisher()
        let waiter = QuickRecordingFinalResultWaiter(publisher: publisher, timeout: .milliseconds(30))
        await assertResult(nil, from: waiter)
        XCTAssertEqual(cancellations.value, 1)
    }

    func testCancellationReleasesSubscriptionAndWaitTask() async {
        let subject = PassthroughSubject<TranscriptionResult, Error>()
        let cancellations = Counter()
        let publisher = subject.handleEvents(receiveCancel: { cancellations.increment() }).eraseToAnyPublisher()
        let waiter = QuickRecordingFinalResultWaiter(publisher: publisher)
        waiter.cancel()
        await assertResult(nil, from: waiter)
        waiter.cancel()
        XCTAssertEqual(cancellations.value, 1)
        subject.send(result("取消后的终稿"))
        XCTAssertNil(waiter.capturedText)
    }

    private func assertResult(_ expected: String?, from waiter: QuickRecordingFinalResultWaiter) async {
        let finished = expectation(description: "Final wait finishes promptly")
        let check = Task {
            let actual = await waiter.task.value
            XCTAssertEqual(actual, expected)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1)
        waiter.cancel()
        check.cancel()
    }

    private func result(_ text: String) -> TranscriptionResult {
        .init(text: text, type: .final, confidence: nil, timestamp: Date(), locale: Locale(identifier: "zh-Hans"))
    }

    private final class Counter: Sendable {
        private let count = Mutex(0)
        var value: Int { count.withLock { $0 } }
        func increment() { count.withLock { $0 += 1 } }
    }

    /// 仅桥接 Combine 非 Sendable subject；引用不可变，send 与订阅使用 Combine 自身同步。
    private final class BackgroundSource: @unchecked Sendable {
        private let subject = PassthroughSubject<TranscriptionResult, Error>()
        var publisher: AnyPublisher<TranscriptionResult, Error> { subject.eraseToAnyPublisher() }
        func send(_ result: TranscriptionResult) { subject.send(result) }
        func complete(fails: Bool) { subject.send(completion: fails ? .failure(CancellationError()) : .finished) }
    }
}
#endif
