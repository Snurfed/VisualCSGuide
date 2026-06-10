import AVFoundation

@MainActor
final class FeedbackSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = FeedbackSpeaker()

    @Published var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func speak(_ text: String) {
        stop()

        // Reconfigure audio session each time
        configureAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func speakFeedback(score: Int, understanding: String, encouragement: String) {
        var speechText = ""

        // Score announcement
        if score >= 80 {
            speechText += "Great job! You scored \(score) out of 100. "
        } else if score >= 60 {
            speechText += "Good effort! You scored \(score) out of 100. "
        } else {
            speechText += "You scored \(score) out of 100. "
        }

        // Understanding summary
        speechText += understanding + " "

        // Encouragement
        speechText += encouragement

        speak(speechText)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - AVSpeechSynthesizerDelegate
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
