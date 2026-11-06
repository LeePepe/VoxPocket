import Foundation
import VoxCore
import VoxLLM
import VoxRefine
import VoxSpeech

package struct BuiltInWorkflowNodeHandler: WorkflowNodeHandler {
    package func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        try Task.checkCancellation()
        switch context.node.kind {
        case .captureMicrophone: return try await capture(context: context)
        case .refineInput:
            let request = try request(from: context)
            if context.node.params["analysis.skip"] != .string("true") {
                context.configuration.logger.info("开始内容分析", fields: [.int("text_length", request.text.count)])
            }
            return .refinementRequest(request)
        case .speechApple, .speechAzureBatch, .speechAzureRealtime, .speechWhisperKitLocal:
            return try await Self.transcribe(context: context)
        case .mergeLLM: return try await merge(context: context)
        case .selectText:
            guard let value = context.inputs.last else { throw WorkflowRuntimeError.nodeFailed }
            return value
        case .analyzeIntent, .analyzeTone, .analyzeEntities, .analyzeTags, .analyzeParams:
            return try await analyze(context: context)
        case .refinePrompt: return .prompt(try prompt(context: context))
        case .llmApple, .llmAzure: return try await complete(context: context)
        case .outputText:
            guard let value = context.inputs.first else { throw WorkflowRuntimeError.nodeFailed }
            return value
        default: throw WorkflowRuntimeError.nodeFailed
        }
    }

    package static func transcribe(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        let session: any SpeechSession
        if case .speechSession(let supplied) = context.inputs.first {
            session = supplied
        } else if case .audio(let capture) = context.inputs.first {
            session = try await capture.session(for: context.node.kind)
        } else {
            let source = try await context.configuration.speechSource(for: context.node.kind)
            let language = context.node.params["language"]?.stringValue ?? "zh-Hans"
            session = try await source.startSession(language: Locale(identifier: language))
        }
        return try await consume(session: session, context: context)
    }

    private func capture(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        let supplied: (any SpeechSession)?
        if case .speechSession(let session) = context.workflowInput { supplied = session } else { supplied = nil }
        let capture = WorkflowAudioCapture(configuration: context.configuration,
            language: Locale(identifier: context.node.params["language"]?.stringValue ?? "zh-Hans"), suppliedSession: supplied)
        do { try await capture.prepare(context.speechNodeKinds) }
        catch { await capture.finish(cancelled: true); throw error }
        return .audio(capture)
    }

    package static func consume(session: any SpeechSession, context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        do {
            let result = try await consumeEvents(session: session, context: context)
            return result
        } catch {
            await session.cancel()
            throw error
        }
    }

    private static func consumeEvents(session: any SpeechSession, context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        var final: TranscriptionResult?
        var lastState: AudioCaptureState?
        events: for try await event in session.events() {
            try Task.checkCancellation()
            switch event {
            case .partial(let result): context.emit(.partial(result))
            case .final(let result):
                final = result
                if context.emitsFinal { context.emit(.final(result)) }
                break events
            case .level(let value): context.emit(.level(value))
            case .state(let value): lastState = value; context.emit(.state(value))
            }
        }
        try Task.checkCancellation()
        guard let final else { throw WorkflowRuntimeError.nodeFailed }
        await session.stop()
        if lastState != .idle { context.emit(.state(.idle)) }
        return WorkflowNodeValue.transcriptionResult(final)
    }

    private func request(from context: WorkflowNodeContext) throws -> RefinementRequest {
        for value in context.inputs + [context.workflowInput] {
            switch value {
            case .refinementRequest(let request): return request
            case .text(let text), .string(let text), .json(.string(let text)): return RefinementRequest(text: text)
            default: continue
            }
        }
        throw WorkflowRuntimeError.nodeFailed
    }

    private func analyze(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        guard context.node.params["analysis.skip"]?.stringValue != "true" else { return .analysis(PartialAnalysis()) }
        let stepName = String(context.node.kind.rawValue.dropFirst("analyze.".count))
        guard let step = AnalysisStep(rawValue: stepName) else { throw WorkflowRuntimeError.nodeFailed }
        let providerName = context.node.params["analysis.\(stepName).provider"]?.stringValue ?? "appleIntelligence"
        guard let type = LLMProviderType(rawValue: providerName), let provider = context.configuration.providers[type] else {
            throw WorkflowRuntimeError.nodeFailed
        }
        let request = try request(from: context)
        let partial = try await provider.analyze(AnalysisRequest(text: request.text, options: request.options,
            transcriptionMetadata: request.transcriptionMetadata), steps: [step])
        switch step {
        case .intent: return .analysis(PartialAnalysis(intent: partial.intent))
        case .tone: return .analysis(PartialAnalysis(tone: partial.tone))
        case .entities: return .analysis(PartialAnalysis(entities: partial.entities))
        case .tags: return .analysis(PartialAnalysis(tags: partial.tags))
        case .params: return .analysis(PartialAnalysis(params: partial.params))
        }
    }

    private func prompt(context: WorkflowNodeContext) throws -> WorkflowPrompt {
        let request = try request(from: context)
        var partial = PartialAnalysis()
        for value in context.inputs {
            guard case .analysis(let analysis) = value else { continue }
            if let intent = analysis.intent { partial.intent = intent }
            if let tone = analysis.tone { partial.tone = tone }
            if let entities = analysis.entities { partial.entities = entities }
            if let tags = analysis.tags { partial.tags = tags }
            if let params = analysis.params { partial.params = params }
        }
        var missing = Set<AnalysisStep>()
        if partial.intent == nil { missing.insert(.intent) }
        if partial.tone == nil { missing.insert(.tone) }
        if partial.entities == nil { missing.insert(.entities) }
        if partial.tags == nil { missing.insert(.tags) }
        if partial.params == nil { missing.insert(.params) }
        if context.node.params["analysis.skip"] != .string("true") {
            context.configuration.logger.info("内容分析完成", fields: [.int("entities_count", partial.entities?.count ?? 0), .int("tags_count", partial.tags?.count ?? 0)])
        }
        return WorkflowPrompt(request: request,
            text: RefinementPromptBuilder.build(text: request.text, customPrompt: request.customPrompt),
            analysis: partial, missingSteps: missing)
    }

    private func complete(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        guard case .prompt(let prompt) = context.inputs.first else { throw WorkflowRuntimeError.nodeFailed }
        let type: LLMProviderType = context.node.kind == .llmAzure ? .azureFoundry : .appleIntelligence
        guard let provider = context.configuration.providers[type] else { throw WorkflowRuntimeError.nodeFailed }
        let text: String
        if context.node.params["streaming"] == .bool(true) {
            var chunks = ""
            for try await chunk in try await provider.completeStreaming(prompt: prompt.text) {
                try Task.checkCancellation()
                context.emit(.refinedChunk(chunk))
                chunks += chunk
            }
            text = chunks
        } else { text = try await provider.complete(prompt: prompt.text) }
        try Task.checkCancellation()
        let intent = prompt.analysis.intent ?? IntentAnalysis()
        let combined = IntentAnalysis(intent: intent.intent, confidence: intent.confidence,
            params: prompt.analysis.params ?? IntentParams(), entities: prompt.analysis.entities ?? [], tags: prompt.analysis.tags ?? [])
        return .response(RefinementResponse(originalText: prompt.request.text, refinedText: text,
            intentAnalysis: combined, toneAnalysis: prompt.analysis.tone ?? ToneAnalysis(), missingAnalysisSteps: prompt.missingSteps))
    }

    private func merge(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        guard context.inputs.count == 2 else { throw WorkflowRuntimeError.nodeFailed }
        let apple = context.inputs[0].jsonValue.stringValue ?? ""
        let other = context.inputs[1].jsonValue.stringValue ?? ""
        let text = await mergedTranscription(appleSpeech: apple, whisper: other, merger: context.configuration.merger)
        try Task.checkCancellation()
        if case .transcriptionResult(let result) = context.inputs[1] {
            return .transcriptionResult(TranscriptionResult(text: text, type: .final, confidence: result.confidence, locale: result.locale))
        }
        return .text(text)
    }
}

extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}
