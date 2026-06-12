import Foundation

public struct OllamaProvider: GenerativeAIProvider, Sendable {
    public let kind: AIProviderKind = .ollama

    private let baseURL: URL
    private let model: String
    private let session: URLSession

    public init(baseURL: URL, model: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    public func availabilityDetail() async -> String {
        await isAvailable()
            ? "Connected to Ollama at \(baseURL.host ?? baseURL.absoluteString) using \(model)."
            : "Ollama is not running at \(baseURL.absoluteString)."
    }

    public func isAvailable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    public func respond(to question: String, context: AIChatContext) async throws -> String {
        let prompt = """
        \(StorageContextFormatter.chatInstructions())

        \(StorageContextFormatter.format(context))

        User question: \(question)
        """
        return try await generate(prompt: prompt)
    }

    public func suggestQuestions(context: AIChatContext) async -> [String] {
        let fallback = RuleBasedChatEngine.defaultSuggestions(for: context)
        guard await isAvailable() else { return fallback }

        let prompt = """
        Suggest four short follow-up questions a Mac user could ask about their storage cleanup.
        Return one question per line with no numbering.
        """
        do {
            let response = try await generate(prompt: prompt)
            let parsed = response
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return parsed.isEmpty ? fallback : Array(parsed.prefix(6))
        } catch {
            return fallback
        }
    }

    public func enrichAnalysis(context: AIChatContext) async throws -> String? {
        let prompt = """
        \(StorageContextFormatter.analysisInstructions())

        \(StorageContextFormatter.format(context))
        """
        let response = try await generate(prompt: prompt)
        return response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : response
    }

    private func generate(prompt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = json?["response"] as? String ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIConsultantError.emptyResponse
        }
        return text
    }
}
