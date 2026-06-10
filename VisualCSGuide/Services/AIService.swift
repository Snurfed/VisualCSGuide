import Foundation

@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    // Backend proxy URL - no API key needed in app
    private let apiBaseURL = "https://visualcsguide-api.vercel.app"

    @Published var isConfigured: Bool = true // Always configured with backend proxy

    private init() {}

    struct ExplanationFeedback {
        let score: Int // 0-100
        let understanding: String
        let strengths: [String]
        let suggestions: [String]
        let encouragement: String
    }

    func evaluateExplanation(
        userExplanation: String,
        expectedAnswer: String,
        question: String,
        conceptTitle: String
    ) async throws -> ExplanationFeedback {

        let requestBody: [String: Any] = [
            "userExplanation": userExplanation,
            "expectedAnswer": expectedAnswer,
            "question": question,
            "conceptTitle": conceptTitle
        ]

        guard let url = URL(string: "\(apiBaseURL)/api/evaluate") else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["error"] as? String {
                throw AIError.serverError(errorMessage)
            }
            throw AIError.httpError(httpResponse.statusCode)
        }

        guard let feedback = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.parseError
        }

        return ExplanationFeedback(
            score: feedback["score"] as? Int ?? 50,
            understanding: feedback["understanding"] as? String ?? "Keep practicing!",
            strengths: feedback["strengths"] as? [String] ?? [],
            suggestions: feedback["suggestions"] as? [String] ?? [],
            encouragement: feedback["encouragement"] as? String ?? "Great effort! Keep learning!"
        )
    }

    enum AIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(Int)
        case parseError
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .invalidResponse:
                return "Invalid response from server"
            case .httpError(let code):
                return "Server error (code \(code))"
            case .parseError:
                return "Failed to parse response"
            case .serverError(let message):
                return message
            }
        }
    }
}
