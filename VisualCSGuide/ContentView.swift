import SwiftUI

struct ContentView: View {
    @StateObject private var deckStore = DeckStore()
    @StateObject private var progressStore = ProgressStore()
    @StateObject private var aiService = AIService.shared
    @StateObject private var storeManager = StoreManager.shared

    var body: some View {
        NavigationStack {
            ModuleListView()
                .environmentObject(deckStore)
                .environmentObject(progressStore)
                .environmentObject(aiService)
                .environmentObject(storeManager)
        }
        .task {
            deckStore.load()
            progressStore.load()
        }
    }
}

struct CurriculumCard: Codable, Identifiable, Hashable {
    let id: String
    let module: String
    let topic: String
    let difficulty: String
    let title: String
    let explanation: String
    let analogy: String
    let tiny_visual_key: String
    let example: String
    let why_it_matters: String
    let checkpoint_question: String
    let expected_answer: String
    let common_mistake: String
    // New fields for advanced content
    let code: String?
    let timeComplexity: String?
    let spaceComplexity: String?
    let keyInsight: String?
    let relatedConcepts: [String]?

    enum CodingKeys: String, CodingKey {
        case id, module, topic, difficulty, title, explanation, analogy
        case tiny_visual_key, example, why_it_matters, checkpoint_question
        case expected_answer, common_mistake, code
        case timeComplexity = "time_complexity"
        case spaceComplexity = "space_complexity"
        case keyInsight = "key_insight"
        case relatedConcepts = "related_concepts"
    }
}

struct CardProgress: Codable {
    var mastery: Int = 0
    var completedCount: Int = 0
    var lastReviewed: Date?
    var nextReview: Date = .distantPast
}

struct LearningStats: Codable {
    var streakDays: Int = 0
    var lastStudyDay: Date?
    var totalReviews: Int = 0
}

@MainActor
final class DeckStore: ObservableObject {
    @Published private(set) var cards: [CurriculumCard] = []

    let curriculumFiles = [
        "foundations",
        "programming-basics",
        "data-structures",
        "algorithms",
        "operating-systems",
        "databases",
        "networking",
        "security",
        "software-engineering",
        "ai-ml",
        "cloud-computing",
        "distributed-systems",
        "compilers",
        "oop",
        "computer-architecture",
        "theory-of-computation",
        "functional-programming",
        "web-development",
        "math-for-cs"
    ]

    var modules: [String] {
        Array(Set(cards.map(\.module))).sorted { lhs, rhs in
            curriculumFiles.firstIndex(of: slug(lhs)) ?? 99 < curriculumFiles.firstIndex(of: slug(rhs)) ?? 99
        }
    }

    func cards(in module: String) -> [CurriculumCard] {
        cards.filter { $0.module == module }
    }

    func load() {
        var loaded: [CurriculumCard] = []
        for file in curriculumFiles {
            guard let url = Bundle.main.url(forResource: file, withExtension: "json", subdirectory: "curriculum") else {
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                loaded.append(contentsOf: try JSONDecoder().decode([CurriculumCard].self, from: data))
            } catch {
                print("Failed to load \(file).json: \(error)")
            }
        }
        cards = loaded
    }

    private func slug(_ module: String) -> String {
        module.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

@MainActor
final class ProgressStore: ObservableObject {
    @Published private(set) var progressByCard: [String: CardProgress] = [:]
    @Published private(set) var stats = LearningStats()

    private let key = "visual_cs_local_progress_v1"
    private let statsKey = "visual_cs_learning_stats_v1"

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: CardProgress].self, from: data) {
            progressByCard = decoded
        } else {
            progressByCard = [:]
        }

        if let data = UserDefaults.standard.data(forKey: statsKey),
           let decoded = try? JSONDecoder().decode(LearningStats.self, from: data) {
            stats = decoded
        }
    }

    func mark(card: CurriculumCard, grade: ReviewGrade) {
        var progress = progressByCard[card.id] ?? CardProgress()
        progress.completedCount += 1
        progress.lastReviewed = Date()

        switch grade {
        case .gotIt:
            progress.mastery = min(progress.mastery + 2, 10)
            progress.nextReview = Calendar.current.date(byAdding: .day, value: max(1, progress.mastery), to: Date()) ?? Date()
        case .almost:
            progress.mastery = min(progress.mastery + 1, 10)
            progress.nextReview = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        case .review:
            progress.mastery = max(progress.mastery - 1, 0)
            progress.nextReview = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        }

        progressByCard[card.id] = progress
        updateStreak()
        save()
    }

    func progress(for cards: [CurriculumCard]) -> Double {
        guard !cards.isEmpty else { return 0 }
        let completed = cards.filter { (progressByCard[$0.id]?.completedCount ?? 0) > 0 }.count
        return Double(completed) / Double(cards.count)
    }

    func dueCards(from cards: [CurriculumCard]) -> [CurriculumCard] {
        let now = Date()
        let due = cards.filter { (progressByCard[$0.id]?.nextReview ?? .distantPast) <= now }
        return due.isEmpty ? cards : due
    }

    private func save() {
        if let data = try? JSONEncoder().encode(progressByCard) {
            UserDefaults.standard.set(data, forKey: key)
        }
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
    }

    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        stats.totalReviews += 1

        guard let lastStudyDay = stats.lastStudyDay else {
            stats.lastStudyDay = today
            stats.streakDays = 1
            return
        }

        let last = calendar.startOfDay(for: lastStudyDay)
        if last == today {
            return
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), last == yesterday {
            stats.streakDays += 1
        } else {
            stats.streakDays = 1
        }
        stats.lastStudyDay = today
    }
}

enum ReviewGrade {
    case gotIt
    case almost
    case review
}

struct ModuleListView: View {
    @EnvironmentObject private var deckStore: DeckStore
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var storeManager: StoreManager
    @State private var showingSettings = false
    @State private var showingPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                ForEach(deckStore.modules, id: \.self) { module in
                    let cards = deckStore.cards(in: module)
                    let isLocked = storeManager.isModuleLocked(module)

                    if isLocked {
                        Button {
                            showingPaywall = true
                        } label: {
                            ModuleRow(
                                module: module,
                                count: cards.count,
                                progress: progressStore.progress(for: cards),
                                firstCard: cards.first,
                                isLocked: true
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            StudySessionView(module: module, cards: progressStore.dueCards(from: cards))
                                .environmentObject(aiService)
                        } label: {
                            ModuleRow(
                                module: module,
                                count: cards.count,
                                progress: progressStore.progress(for: cards),
                                firstCard: cards.first,
                                isLocked: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(22)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("CS Micro-lessons")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                StreakPill(days: progressStore.stats.streakDays)
            }
            Text("One idea, one visual, one recall prompt.")
                .font(.headline)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            CurriculumProgressHeader(progress: curriculumProgress)
        }
    }
}

struct StreakPill: View {
    let days: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
            Text("\(days)")
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(days) day learning streak")
    }
}

struct CurriculumProgressHeader: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Curriculum completion")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(AppTheme.teal)
            }
            ProgressView(value: progress)
                .tint(AppTheme.teal)
        }
    }
}

private extension ModuleListView {
    var curriculumProgress: Double {
        progressStore.progress(for: deckStore.cards)
    }
}

struct ModuleRow: View {
    let module: String
    let count: Int
    let progress: Double
    let firstCard: CurriculumCard?
    var isLocked: Bool = false

    var iconName: String {
        let m = module.lowercased()
        if m.contains("foundation") { return "building.columns.fill" }
        if m.contains("programming") { return "chevron.left.forwardslash.chevron.right" }
        if m.contains("data structure") { return "square.stack.3d.up.fill" }
        if m.contains("algorithm") { return "arrow.trianglehead.branch" }
        if m.contains("operating") { return "cpu.fill" }
        if m.contains("database") { return "cylinder.fill" }
        if m.contains("network") { return "network" }
        if m.contains("security") { return "lock.shield.fill" }
        if m.contains("software") { return "hammer.fill" }
        if m.contains("ai") || m.contains("machine") { return "brain.head.profile" }
        if m.contains("cloud") { return "cloud.fill" }
        if m.contains("distributed") { return "point.3.connected.trianglepath.dotted" }
        if m.contains("compiler") { return "gearshape.2.fill" }
        if m.contains("oop") || m.contains("object-oriented") { return "cube.fill" }
        if m.contains("architecture") { return "cpu.fill" }
        if m.contains("theory") || m.contains("computation") { return "function" }
        if m.contains("functional") { return "arrow.triangle.branch" }
        if m.contains("web") { return "globe" }
        if m.contains("math") { return "sum" }
        return "book.fill"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.title2.weight(.medium))
                .foregroundStyle(AppTheme.teal)
                .frame(width: 50, height: 50)
                .background(AppTheme.softTeal, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(module)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("\(count) cards")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            if isLocked {
                LockedModuleOverlay()
            } else {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.faint)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .opacity(isLocked ? 0.7 : 1.0)
    }
}

struct StudySessionView: View {
    let module: String
    let cards: [CurriculumCard]

    @State private var index = 0

    var body: some View {
        VStack(spacing: 0) {
            if cards.isEmpty {
                EmptyDeckView()
            } else {
                VStack(spacing: 0) {
                    // Dot progress indicator
                    HStack(spacing: 6) {
                        ForEach(0..<cards.count, id: \.self) { i in
                            Circle()
                                .fill(i == index ? AppTheme.teal : AppTheme.line)
                                .frame(width: i == index ? 8 : 6, height: i == index ? 8 : 6)
                                .animation(.easeInOut(duration: 0.2), value: index)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    // Swipeable cards
                    TabView(selection: $index) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                            MicroLessonCard(card: card)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(module)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MicroLessonCard: View {
    let card: CurriculumCard
    @EnvironmentObject private var aiService: AIService
    @State private var showingVoiceExplanation = false
    @State private var showingAnswer = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header: Icon + Title + Difficulty
                HStack(spacing: 12) {
                    ConceptIcon(topic: card.topic, title: card.title)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text(card.difficulty)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                // Analogy
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.teal)
                    Text(card.analogy)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.teal)
                        .italic()
                }

                // Main explanation
                Text(card.explanation)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(4)

                // Code block (if present)
                if let code = card.code, !code.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Code")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.muted)
                        Text(code)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(AppTheme.ink)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                // Complexity (if present)
                if card.timeComplexity != nil || card.spaceComplexity != nil {
                    HStack(spacing: 16) {
                        if let time = card.timeComplexity {
                            ComplexityBadge(label: "Time", value: time, color: .blue)
                        }
                        if let space = card.spaceComplexity {
                            ComplexityBadge(label: "Space", value: space, color: .purple)
                        }
                        Spacer()
                    }
                }

                // Key Insight (if present)
                if let insight = card.keyInsight, !insight.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                        Text(insight)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(3)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }

                // Example
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Example")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        Text(card.example)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                            .lineSpacing(3)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                // Checkpoint Question
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .font(.subheadline)
                            .foregroundStyle(.purple)
                        Text("Test Your Understanding")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.purple)
                    }

                    Text(card.checkpoint_question)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.ink)

                    HStack(spacing: 12) {
                        Button {
                            showingVoiceExplanation = true
                        } label: {
                            Label("Explain", systemImage: "mic.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.purple, in: Capsule())
                        }

                        Button {
                            withAnimation {
                                showingAnswer.toggle()
                            }
                        } label: {
                            Label(showingAnswer ? "Hide" : "Reveal", systemImage: showingAnswer ? "eye.slash" : "eye")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.purple.opacity(0.12), in: Capsule())
                        }
                    }

                    if showingAnswer {
                        Text(card.expected_answer)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .sheet(isPresented: $showingVoiceExplanation) {
            VoiceExplanationSheet(
                question: card.checkpoint_question,
                expectedAnswer: card.expected_answer,
                conceptTitle: card.title,
                onDismiss: { showingVoiceExplanation = false },
                aiService: aiService
            )
        }
    }
}

struct ComplexityBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color.opacity(0.8))
            Text(value)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: Capsule())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

struct MicroSection<Content: View>: View {
    let label: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.heavy))
                .foregroundStyle(AppTheme.teal)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ConceptIcon: View {
    let topic: String
    let title: String

    var iconName: String {
        let t = topic.lowercased()
        let ti = title.lowercased()

        if t.contains("algorithm") || ti.contains("algorithm") { return "arrow.trianglehead.branch" }
        if t.contains("stack") || ti.contains("stack") { return "square.stack.3d.up.fill" }
        if t.contains("queue") || ti.contains("queue") { return "arrow.right.to.line" }
        if t.contains("tree") || ti.contains("tree") { return "point.3.connected.trianglepath.dotted" }
        if t.contains("graph") || ti.contains("graph") { return "circle.grid.cross.fill" }
        if t.contains("hash") || ti.contains("hash") { return "number" }
        if t.contains("array") || ti.contains("array") { return "rectangle.split.3x1.fill" }
        if t.contains("linked") || ti.contains("linked") { return "link" }
        if t.contains("search") || ti.contains("search") { return "magnifyingglass" }
        if t.contains("sort") || ti.contains("sort") { return "arrow.up.arrow.down" }
        if t.contains("recursion") || ti.contains("recursion") { return "repeat" }
        if t.contains("loop") || ti.contains("loop") { return "repeat.circle.fill" }
        if t.contains("variable") || ti.contains("variable") { return "x.squareroot" }
        if t.contains("function") || ti.contains("function") { return "function" }
        if t.contains("class") || ti.contains("object") { return "cube.fill" }
        if t.contains("database") || ti.contains("sql") { return "cylinder.fill" }
        if t.contains("network") || ti.contains("internet") { return "network" }
        if t.contains("security") || ti.contains("encrypt") { return "lock.fill" }
        if t.contains("memory") || ti.contains("ram") { return "memorychip.fill" }
        if t.contains("cpu") || ti.contains("processor") { return "cpu.fill" }
        if t.contains("binary") || ti.contains("bit") { return "01.square.fill" }
        if t.contains("computer science") { return "desktopcomputer" }
        if t.contains("programming") || ti.contains("code") { return "chevron.left.forwardslash.chevron.right" }
        if t.contains("ai") || t.contains("machine learning") { return "brain.head.profile" }

        return "lightbulb.min.fill"
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(AppTheme.teal)
            .frame(width: 48, height: 48)
            .background(AppTheme.softTeal, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AIFeedback {
    enum Rating { case good, partial, needsWork }
    let rating: Rating
    let summary: String
    let strengths: [String]
    let suggestions: [String]

    var ratingColor: Color {
        switch rating {
        case .good: return AppTheme.teal
        case .partial: return .orange
        case .needsWork: return .red
        }
    }

    var ratingIcon: String {
        switch rating {
        case .good: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .needsWork: return "arrow.counterclockwise.circle.fill"
        }
    }
}

struct AIFeedbackView: View {
    let feedback: AIFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: feedback.ratingIcon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(feedback.ratingColor)
                Text("AI Feedback")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(feedback.ratingColor)
            }

            Text(feedback.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            if !feedback.strengths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(feedback.strengths, id: \.self) { strength in
                        Label(strength, systemImage: "checkmark")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.teal)
                    }
                }
            }

            if !feedback.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(feedback.suggestions, id: \.self) { suggestion in
                        Label(suggestion, systemImage: "lightbulb")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(feedback.ratingColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(feedback.ratingColor.opacity(0.3), lineWidth: 1)
        }
    }
}




struct CheckpointView: View {
    let cards: [CurriculumCard]
    let aiReviewEnabled: Bool
    let onComplete: (ReviewGrade) -> Void

    @State private var currentQuestionIndex = 0
    @State private var answer = ""
    @State private var showingFeedback = false
    @State private var aiFeedback: AIFeedback?
    @State private var isAnalyzing = false
    @FocusState private var isInputFocused: Bool

    private var currentCard: CurriculumCard? {
        cards.indices.contains(currentQuestionIndex) ? cards[currentQuestionIndex] : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Progress
                    HStack {
                        Text("Question \(currentQuestionIndex + 1) of \(cards.count)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(AppTheme.muted)
                        Spacer()
                    }

                    if let card = currentCard {
                        // Topic pill
                        Text(card.topic)
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(AppTheme.teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.softTeal, in: Capsule())

                        // Question
                        Text(card.checkpoint_question)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.ink)

                        if !showingFeedback {
                            // Answer input
                            TextField("Explain in your own words...", text: $answer, axis: .vertical)
                                .font(.body)
                                .lineLimit(4...8)
                                .padding(14)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(AppTheme.line, lineWidth: 1)
                                }
                                .focused($isInputFocused)

                            // Check button
                            Button(action: checkAnswer) {
                                HStack(spacing: 8) {
                                    if isAnalyzing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: aiReviewEnabled ? "sparkles" : "eye")
                                    }
                                    Text(isAnalyzing ? "Checking..." : (aiReviewEnabled ? "Check with AI" : "Show Answer"))
                                }
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(answer.isEmpty && aiReviewEnabled ? AppTheme.faint : AppTheme.teal, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(answer.isEmpty && aiReviewEnabled || isAnalyzing)
                        } else {
                            // Feedback view
                            if let feedback = aiFeedback {
                                AIFeedbackView(feedback: feedback)
                            }

                            // Model answer
                            MicroSection(label: "Model Answer", icon: "checkmark.seal.fill") {
                                Text(card.expected_answer)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(AppTheme.ink)
                            }

                            // Next / Done button
                            Button(action: nextQuestion) {
                                Text(currentQuestionIndex < cards.count - 1 ? "Next Question" : "Done")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(AppTheme.teal, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
                .padding(22)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Quick Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip All") {
                        onComplete(.gotIt)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private func checkAnswer() {
        isInputFocused = false

        if aiReviewEnabled && !answer.isEmpty {
            isAnalyzing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let card = currentCard {
                    aiFeedback = analyzeAnswer(userAnswer: answer, card: card)
                }
                isAnalyzing = false
                withAnimation(.spring(response: 0.3)) {
                    showingFeedback = true
                }
            }
        } else {
            withAnimation(.spring(response: 0.3)) {
                showingFeedback = true
            }
        }
    }

    private func nextQuestion() {
        if currentQuestionIndex < cards.count - 1 {
            withAnimation(.spring(response: 0.3)) {
                currentQuestionIndex += 1
                answer = ""
                showingFeedback = false
                aiFeedback = nil
            }
        } else {
            onComplete(.gotIt)
        }
    }

    private func analyzeAnswer(userAnswer: String, card: CurriculumCard) -> AIFeedback {
        let answer = userAnswer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = card.expected_answer.lowercased()

        let keywords = Set(expected.split(separator: " ").filter { $0.count > 4 }.map { String($0) })
        let userWords = Set(answer.split(separator: " ").map { String($0) })
        let matchCount = keywords.intersection(userWords).count
        let matchRatio = keywords.isEmpty ? 0 : Double(matchCount) / Double(keywords.count)

        if matchRatio > 0.5 || answer.count > 50 {
            return AIFeedback(
                rating: .good,
                summary: "Good understanding!",
                strengths: ["You captured the main idea"],
                suggestions: []
            )
        } else if answer.count > 20 {
            return AIFeedback(
                rating: .partial,
                summary: "Partial understanding",
                strengths: ["You made an attempt"],
                suggestions: ["Compare with the model answer below"]
            )
        } else {
            return AIFeedback(
                rating: .needsWork,
                summary: "Keep practicing",
                strengths: [],
                suggestions: ["Review the concept and try again"]
            )
        }
    }
}


struct ExplainSheet: View {
    let card: CurriculumCard

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(card.title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    MicroSection(label: "Concept", icon: "text.book.closed.fill") {
                        Text(card.explanation)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.ink)
                    }
                    MicroSection(label: "Why it matters", icon: "star.fill") {
                        Text(card.why_it_matters)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.ink)
                    }
                    MicroSection(label: "Common mistake", icon: "exclamationmark.triangle.fill") {
                        Text(card.common_mistake)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.ink)
                    }
                    MicroSection(label: "Expected answer", icon: "checkmark.seal.fill") {
                        Text(card.expected_answer)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                .padding(22)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Explain")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


struct ModuleCompletionView: View {
    let module: String
    let total: Int
    let gotItCount: Int
    let reviewCount: Int
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppTheme.teal)

            Text("Module complete")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Text(module)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            HStack(spacing: 12) {
                SummaryMetric(title: "Lessons", value: "\(total)", tint: AppTheme.teal)
                SummaryMetric(title: "Got it", value: "\(gotItCount)", tint: AppTheme.teal)
                SummaryMetric(title: "Review", value: "\(reviewCount)", tint: .red)
            }
            .padding(.horizontal, 18)

            Text("Anything marked for review will come back later through the local spaced repetition schedule.")
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button(action: onRestart) {
                Text("Study again")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 28)

            Spacer()
        }
        .background(AppTheme.background.ignoresSafeArea())
    }
}

struct SummaryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.line, lineWidth: 1)
        }
    }
}

struct StudyProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lesson \(current) of \(total)")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Text("\(Int((Double(current) / Double(max(total, 1))) * 100))%")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(AppTheme.teal)
            }
            ProgressView(value: Double(current), total: Double(max(total, 1)))
                .tint(AppTheme.teal)
        }
    }
}


struct InfoPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .foregroundStyle(AppTheme.teal)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.softTeal, in: Capsule())
    }
}

struct GradeButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct EmptyDeckView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.faint)
            Text("No cards due")
                .font(.title2.weight(.bold))
            Text("You are caught up for now.")
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}

enum AppTheme {
    static let background = Color(red: 0.98, green: 0.985, blue: 0.975)
    static let paper = Color(red: 0.94, green: 0.965, blue: 0.955)
    static let softTeal = Color(red: 0.87, green: 0.98, blue: 0.95)
    static let teal = Color(red: 0.02, green: 0.58, blue: 0.48)
    static let ink = Color(red: 0.08, green: 0.11, blue: 0.13)
    static let muted = Color(red: 0.40, green: 0.46, blue: 0.50)
    static let faint = Color(red: 0.62, green: 0.67, blue: 0.70)
    static let line = Color(red: 0.86, green: 0.89, blue: 0.88)
}
