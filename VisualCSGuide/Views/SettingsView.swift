import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if storeManager.isProUnlocked {
                        HStack {
                            Image(systemName: "star.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Pro Unlocked")
                                .font(.headline)
                            Spacer()
                            Text("All modules")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "star.circle.fill")
                                    .foregroundStyle(.orange)
                                Text("Unlock Full Curriculum")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let product = storeManager.product {
                                    Text(product.displayPrice)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        Button {
                            Task {
                                await storeManager.restorePurchases()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.blue)
                                Text("Restore Purchases")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } header: {
                    Text("Subscription")
                }

                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Voice Explanations Enabled")
                            .font(.headline)
                    }
                    .padding(.vertical, 4)

                    Text("Explain concepts in your own words and get AI-powered feedback to reinforce your learning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("AI Features")
                }

                Section {
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.blue)
                        Text("Speech Recognition")
                        Spacer()
                        Text("Built-in")
                            .foregroundStyle(.secondary)
                    }

                    Text("Voice recognition uses Apple's built-in speech framework. No additional setup required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Voice Features")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "questionmark.circle")
                            .font(.headline)

                        Text("1. Tap 'Explain' on any checkpoint question")
                        Text("2. Speak your understanding of the concept")
                        Text("3. AI analyzes your explanation and gives feedback")
                        Text("4. Learn from strengths and suggestions")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                } header: {
                    Text("About Voice Explanations")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Cards")
                        Spacer()
                        Text("580")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("App Info")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }
}

#Preview {
    SettingsView()
}
