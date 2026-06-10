import SwiftUI
import AVFoundation

struct VoiceExplanationSheet: View {
    let question: String
    let expectedAnswer: String
    let conceptTitle: String
    let onDismiss: () -> Void

    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var speaker = FeedbackSpeaker.shared
    @ObservedObject var aiService: AIService

    @State private var feedback: AIService.ExplanationFeedback?
    @State private var isEvaluating: Bool = false
    @State private var errorMessage: String?
    @State private var showExpectedAnswer: Bool = false
    @State private var textInput: String = ""
    @State private var useTextInput: Bool = false
    @State private var displayedScore: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Question
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Question", systemImage: "questionmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.blue)
                        Text(question)
                            .font(.body.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                    // Input Section
                    if feedback == nil {
                        if useTextInput {
                            textInputSection
                        } else {
                            recordingSection
                        }
                    }

                    // Your Answer (voice mode)
                    if !useTextInput && !speechRecognizer.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your Answer", systemImage: "text.quote")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(speechRecognizer.transcript)
                                .font(.body)
                                .italic()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Your Answer (text mode)
                    if useTextInput && !textInput.isEmpty && feedback != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your Answer", systemImage: "text.quote")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(textInput)
                                .font(.body)
                                .italic()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Error
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Feedback
                    if let feedback = feedback {
                        feedbackView(feedback)
                    }

                    // Loading
                    if isEvaluating {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Analyzing your explanation...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }

                    // Show Expected Answer toggle
                    if feedback != nil || showExpectedAnswer {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation {
                                    showExpectedAnswer.toggle()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: showExpectedAnswer ? "eye.slash" : "eye")
                                    Text(showExpectedAnswer ? "Hide Expected Answer" : "Show Expected Answer")
                                }
                                .font(.caption.weight(.medium))
                            }

                            if showExpectedAnswer {
                                Text(expectedAnswer)
                                    .font(.subheadline)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Explain It")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        speaker.stop()
                        speechRecognizer.reset()
                        onDismiss()
                    }
                }

                if feedback != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Try Again") {
                            resetForRetry()
                        }
                    }
                }
            }
        }
        .onAppear {
            speechRecognizer.checkAuthorization()
        }
        .onDisappear {
            speaker.stop()
        }
    }

    // MARK: - Text Input Section
    @ViewBuilder
    private var textInputSection: some View {
        VStack(spacing: 16) {
            TextField("Type your explanation here...", text: $textInput, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .frame(minHeight: 100, alignment: .topLeading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button {
                    useTextInput = false
                } label: {
                    Label("Use Voice", systemImage: "mic.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }

                Button {
                    submitTextForEvaluation()
                } label: {
                    Label("Get Feedback", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue, in: Capsule())
                }
                .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Recording Section
    @ViewBuilder
    private var recordingSection: some View {
        VStack(spacing: 16) {
            // Mic button
            Button {
                toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(micButtonColor)
                        .frame(width: 80, height: 80)

                    if case .recording = speechRecognizer.state {
                        Circle()
                            .stroke(Color.red, lineWidth: 3)
                            .frame(width: 90, height: 90)
                            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            .opacity(pulseAnimation ? 0.5 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulseAnimation)
                            .onAppear { pulseAnimation = true }
                            .onDisappear { pulseAnimation = false }
                    }

                    Image(systemName: micIconName)
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
            }
            .disabled(isEvaluating)

            Text(recordingInstructions)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Submit button (voice mode)
            if case .finished = speechRecognizer.state {
                Button {
                    submitForEvaluation()
                } label: {
                    Label("Get Feedback", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue, in: Capsule())
                }
            }

            // Text input fallback button
            Button {
                useTextInput = true
            } label: {
                Label("Type Instead", systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    @State private var pulseAnimation = false

    private var micButtonColor: Color {
        switch speechRecognizer.state {
        case .recording: return .red
        case .processing: return .orange
        case .error: return .gray
        default: return .blue
        }
    }

    private var micIconName: String {
        switch speechRecognizer.state {
        case .recording: return "stop.fill"
        case .processing: return "waveform"
        case .error: return "mic.slash.fill"
        default: return "mic.fill"
        }
    }

    private var recordingInstructions: String {
        if !speechRecognizer.isAuthorized {
            return "Microphone access required. Enable in Settings or type instead."
        }

        switch speechRecognizer.state {
        case .idle: return "Tap the microphone and explain the concept in your own words"
        case .requesting: return "Starting..."
        case .recording: return "Listening... Tap to stop when done"
        case .processing: return "Processing your speech..."
        case .finished: return "Ready to submit for feedback"
        case .error(let msg): return "Error: \(msg). Try typing instead."
        }
    }

    private func toggleRecording() {
        switch speechRecognizer.state {
        case .idle, .finished, .error:
            speechRecognizer.startRecording()
        case .recording:
            speechRecognizer.stopRecording()
        default:
            break
        }
    }

    private func submitForEvaluation() {
        guard !speechRecognizer.transcript.isEmpty else { return }
        evaluate(explanation: speechRecognizer.transcript)
    }

    private func submitTextForEvaluation() {
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        evaluate(explanation: trimmed)
    }

    private func evaluate(explanation: String) {
        isEvaluating = true
        errorMessage = nil
        displayedScore = 0

        Task {
            do {
                let result = try await aiService.evaluateExplanation(
                    userExplanation: explanation,
                    expectedAnswer: expectedAnswer,
                    question: question,
                    conceptTitle: conceptTitle
                )
                feedback = result

                // Animate score
                animateScore(to: result.score)

                // Haptic feedback
                provideHaptic(for: result.score)

                // Speak the feedback
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    speaker.speakFeedback(
                        score: result.score,
                        understanding: result.understanding,
                        encouragement: result.encouragement
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isEvaluating = false
        }
    }

    private func animateScore(to target: Int) {
        displayedScore = 0
        let duration: Double = 1.0
        let steps = min(target, 50)
        let stepDuration = duration / Double(steps)

        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                withAnimation(.easeOut(duration: 0.05)) {
                    displayedScore = Int(Double(target) * Double(i) / Double(steps))
                }
            }
        }
    }

    private func provideHaptic(for score: Int) {
        let generator = UINotificationFeedbackGenerator()
        if score >= 80 {
            generator.notificationOccurred(.success)
        } else if score >= 50 {
            generator.notificationOccurred(.warning)
        }
    }

    private func resetForRetry() {
        speaker.stop()
        feedback = nil
        errorMessage = nil
        showExpectedAnswer = false
        textInput = ""
        displayedScore = 0
        speechRecognizer.reset()
    }

    // MARK: - Feedback View
    @ViewBuilder
    private func feedbackView(_ feedback: AIService.ExplanationFeedback) -> some View {
        VStack(spacing: 16) {
            // Score with animation
            ZStack {
                Circle()
                    .stroke(scoreColor(feedback.score).opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: CGFloat(displayedScore) / 100.0)
                    .stroke(scoreColor(feedback.score), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.0), value: displayedScore)

                VStack(spacing: 2) {
                    Text("\(displayedScore)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor(feedback.score))
                    Text("Score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)

            // Understanding summary
            Text(feedback.understanding)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Replay button
            Button {
                speaker.speakFeedback(
                    score: feedback.score,
                    understanding: feedback.understanding,
                    encouragement: feedback.encouragement
                )
            } label: {
                Label(speaker.isSpeaking ? "Speaking..." : "Replay Feedback", systemImage: speaker.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.purple)
            }
            .disabled(speaker.isSpeaking)

            // Strengths
            if !feedback.strengths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What You Got Right", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)

                    ForEach(feedback.strengths, id: \.self) { strength in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(strength)
                                .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }

            // Suggestions
            if !feedback.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("To Improve", systemImage: "lightbulb.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)

                    ForEach(feedback.suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(suggestion)
                                .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }

            // Encouragement
            Text(feedback.encouragement)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.blue)
                .padding()
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
}

#Preview {
    VoiceExplanationSheet(
        question: "What are the three things a computer does with information?",
        expectedAnswer: "A computer takes information in (input), processes it, and gives information out (output).",
        conceptTitle: "What is a Computer?",
        onDismiss: {},
        aiService: AIService.shared
    )
}
