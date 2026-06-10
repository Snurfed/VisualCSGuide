import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {
    enum RecognitionState {
        case idle
        case requesting
        case recording
        case processing
        case finished(String)
        case error(String)
    }

    @Published private(set) var state: RecognitionState = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var isAuthorized: Bool = false

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.isAuthorized = status == .authorized
            }
        }
    }

    func startRecording() {
        guard isAuthorized else {
            state = .error("Speech recognition not authorized")
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("Speech recognition not available")
            return
        }

        state = .requesting
        transcript = ""

        do {
            try setupAudioSession()
            try startAudioEngine()
            state = .recording
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        state = .processing

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if case .processing = self.state {
                self.state = .finished(self.transcript)
            }
        }
    }

    func reset() {
        stopRecording()
        transcript = ""
        state = .idle
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func setupAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startAudioEngine() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.transcript = result.bestTranscription.formattedString

                    if result.isFinal {
                        self.state = .finished(self.transcript)
                    }
                }

                if let error = error {
                    if (error as NSError).code != 1 { // Ignore cancellation
                        self.state = .error(error.localizedDescription)
                    }
                }
            }
        }
    }
}
