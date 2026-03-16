import XCTest
@testable import Observability

final class PrintLoggerTimestampTests: XCTestCase {
    func testLogOutputIncludesFractionalSecondsInTimestamp() {
        let logger = PrintLogger(subsystem: "TimestampTest")

        let output = captureStandardOutput {
            logger.info("timestamp check", file: #fileID, function: #function, line: #line)
        }

        XCTAssertNotNil(
            output.range(
                of: #"T\d{2}:\d{2}:\d{2}\.\d{2,}Z"#,
                options: .regularExpression
            )
        )
    }

    private func captureStandardOutput(_ body: () -> Void) -> String {
        let pipe = Pipe()
        let stdoutFileDescriptor = dup(STDOUT_FILENO)
        XCTAssertNotEqual(stdoutFileDescriptor, -1)

        fflush(stdout)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        body()

        fflush(stdout)
        dup2(stdoutFileDescriptor, STDOUT_FILENO)
        close(stdoutFileDescriptor)
        pipe.fileHandleForWriting.closeFile()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pipe.fileHandleForReading.closeFile()

        return String(decoding: data, as: UTF8.self)
    }
}
