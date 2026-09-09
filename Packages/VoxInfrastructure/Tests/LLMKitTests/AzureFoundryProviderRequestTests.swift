import XCTest
@testable import LLMKit
import CoreModels

final class AzureFoundryProviderRequestTests: XCTestCase {
    final class Box<T>: @unchecked Sendable {
        var value: T?
    }

    final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                fatalError("MockURLProtocol.requestHandler 未设置")
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.requestHandler = nil
    }

    func testCompleteUsesBearerAuthorizationAndFoundryCompletionsEndpoint() async throws {
        let capturedRequest = Box<URLRequest>()

        MockURLProtocol.requestHandler = { request in
            capturedRequest.value = request

            let body = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }

        let session = makeSession()
        let provider = AzureFoundryProvider(
            config: LLMProviderConfig(
                providerType: .azureFoundry,
                apiKey: "test-key",
                baseURL: URL(string: "https://usllm.services.ai.azure.com")!,
                modelIdentifier: "Kimi-K2.5",
                options: ["azure.api_version": "2024-05-01-preview"]
            ),
            session: session
        )

        _ = try await provider.complete(prompt: "hello")

        let request = try XCTUnwrap(capturedRequest.value)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.url?.absoluteString, "https://usllm.services.ai.azure.com/models/chat/completions?api-version=2024-05-01-preview")
    }

    func testCompleteUsesAPIKeyHeaderForProjectEndpoint() async throws {
        let capturedRequest = Box<URLRequest>()

        MockURLProtocol.requestHandler = { request in
            capturedRequest.value = request

            let body = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }

        let session = makeSession()
        let provider = AzureFoundryProvider(
            config: LLMProviderConfig(
                providerType: .azureFoundry,
                apiKey: "test-key",
                baseURL: URL(string: "https://voxpocketllm.services.ai.azure.com/api/projects/voxpocketllm")!,
                modelIdentifier: "gpt-4.1-mini",
                options: ["azure.api_version": "2024-05-01-preview"]
            ),
            session: session
        )

        _ = try await provider.complete(prompt: "hello")

        let request = try XCTUnwrap(capturedRequest.value)
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "test-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.url?.absoluteString, "https://voxpocketllm.services.ai.azure.com/api/projects/voxpocketllm/models/chat/completions?api-version=2024-05-01-preview")
    }

    func testCompleteRequestBodyContainsFoundryFields() async throws {
        let capturedBody = Box<Data>()

        MockURLProtocol.requestHandler = { request in
            capturedBody.value = Self.extractBody(from: request)

            let body = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }

        let session = makeSession()
        let provider = AzureFoundryProvider(
            config: LLMProviderConfig(
                providerType: .azureFoundry,
                apiKey: "test-key",
                baseURL: URL(string: "https://usllm.services.ai.azure.com")!,
                modelIdentifier: "Kimi-K2.5"
            ),
            session: session
        )

        _ = try await provider.complete(prompt: "I am going to Paris")

        let bodyData = try XCTUnwrap(capturedBody.value)
        let jsonObject = try JSONSerialization.jsonObject(with: bodyData)
        let json = try XCTUnwrap(jsonObject as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "Kimi-K2.5")
        XCTAssertEqual(json["max_tokens"] as? Int, 2048)
        XCTAssertEqual(json["top_p"] as? Double, 0.1)
        XCTAssertEqual(json["presence_penalty"] as? Int, 0)
        XCTAssertEqual(json["temperature"] as? Double, 0.2)

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        XCTAssertEqual(messages.last?["content"] as? String, "I am going to Paris")
    }

    func testDeploymentConfigCanBuildProviderConfig() throws {
        let deployment = AzureFoundryDeployment(
            name: "kimi-prod",
            endpoint: URL(string: "https://usllm.services.ai.azure.com")!,
            model: "Kimi-K2.5",
            apiKey: "secret-123",
            apiVersion: "2024-05-01-preview",
            authMode: .bearer
        )

        let providerConfig = deployment.providerConfig
        XCTAssertEqual(providerConfig.providerType, .azureFoundry)
        XCTAssertEqual(providerConfig.modelIdentifier, "Kimi-K2.5")
        XCTAssertEqual(providerConfig.baseURL?.absoluteString, "https://usllm.services.ai.azure.com")
        XCTAssertEqual(providerConfig.apiKey, "secret-123")
        XCTAssertEqual(providerConfig.options["azure.api_version"], "2024-05-01-preview")
        XCTAssertEqual(providerConfig.options["azure.auth_mode"], "bearer")
    }

    func testLunaUsesV1WithoutLegacySamplingFields() async throws {
        for suffix in ["", "/openai/v1/", "/openai/v1/chat/completions"] {
            MockURLProtocol.requestHandler = { request in
                XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/openai/v1/chat/completions")
                XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "test-key")
                let data = try XCTUnwrap(Self.extractBody(from: request))
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(body["model"] as? String, "custom-deployment")
                XCTAssertEqual(body["reasoning_effort"] as? String, "none")
                XCTAssertEqual(body["max_completion_tokens"] as? Int, 512)
                for key in ["max_tokens", "temperature", "top_p", "presence_penalty"] {
                    XCTAssertNil(body[key])
                }
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"几点开始？"}}]}"#.utf8))
            }
            let deployment = AzureFoundryDeployment(
                name: "test", endpoint: URL(string: "https://example.invalid" + suffix)!,
                model: "custom-deployment", apiKey: "test-key", authMode: .apiKey,
                maxTokens: 512, apiStyle: .openAIV1, reasoningEffort: "none"
            )
            let output = try await AzureFoundryProvider(deployment: deployment, session: makeSession()).complete(prompt: "几点开始")
            XCTAssertEqual(output, "几点开始？")
        }
    }

    func testErrorsDoNotExposeServerBodyAndTruncatedOutputIsRejected() async throws {
        for status in [400, 200] {
            MockURLProtocol.requestHandler = { request in
                let body = status == 400 ? #"{"error":{"message":"PRIVATE_INPUT"}}"#
                    : #"{"choices":[{"finish_reason":"length","message":{"content":"PRIVATE_INPUT"}}]}"#
                return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            let provider = AzureFoundryProvider(config: .init(
                providerType: .azureFoundry, apiKey: "test-key", baseURL: URL(string: "https://example.invalid")!, modelIdentifier: "test"
            ), session: makeSession())
            do {
                _ = try await provider.complete(prompt: "fixture")
                XCTFail("Expected failure")
            } catch {
                XCTAssertFalse(String(describing: error).contains("PRIVATE_INPUT"))
            }
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func extractBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
