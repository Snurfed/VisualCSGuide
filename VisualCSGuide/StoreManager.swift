import StoreKit
import SwiftUI

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published private(set) var isProUnlocked: Bool = false
    @Published private(set) var product: Product?
    @Published private(set) var purchaseError: String?
    @Published private(set) var isLoading: Bool = false

    private let productID = "com.snurfed.csmicrolessons.pro"
    private let unlockedKey = "pro_unlocked"

    private init() {
        isProUnlocked = UserDefaults.standard.bool(forKey: unlockedKey)

        Task {
            await loadProduct()
            await listenForTransactions()
        }
    }

    var freeModules: Set<String> {
        ["Foundations", "Programming Basics", "Data Structures"]
    }

    func isModuleLocked(_ module: String) -> Bool {
        !isProUnlocked && !freeModules.contains(module)
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [productID])
            product = products.first
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase() async {
        guard let product = product else { return }

        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(_):
                    await unlockPro()
                case .unverified(_, _):
                    purchaseError = "Purchase could not be verified"
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval"
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isLoading = false
    }

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil

        do {
            try await AppStore.sync()

            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
                    if transaction.productID == productID {
                        await unlockPro()
                        isLoading = false
                        return
                    }
                }
            }

            purchaseError = "No purchases to restore"
        } catch {
            purchaseError = error.localizedDescription
        }

        isLoading = false
    }

    private func unlockPro() async {
        isProUnlocked = true
        UserDefaults.standard.set(true, forKey: unlockedKey)
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == productID {
                    await unlockPro()
                }
                await transaction.finish()
            }
        }
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(AppTheme.teal)

                        Text("Unlock Full Curriculum")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)

                        Text("Get access to all 19 modules and 580 cards")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(icon: "checkmark.circle.fill", text: "All 19 CS modules")
                        FeatureRow(icon: "checkmark.circle.fill", text: "580 micro-lessons with analogies")
                        FeatureRow(icon: "checkmark.circle.fill", text: "Code examples & complexity analysis")
                        FeatureRow(icon: "checkmark.circle.fill", text: "AI-powered voice explanations")
                        FeatureRow(icon: "checkmark.circle.fill", text: "Spaced repetition learning")
                        FeatureRow(icon: "checkmark.circle.fill", text: "Lifetime access, one-time purchase")
                    }
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.05), radius: 10)

                    // Price button
                    if let product = store.product {
                        Button {
                            Task {
                                await store.purchase()
                            }
                        } label: {
                            HStack {
                                if store.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Unlock for \(product.displayPrice)")
                                        .font(.headline.weight(.bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(AppTheme.teal, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(store.isLoading)
                    } else {
                        ProgressView("Loading...")
                    }

                    // Restore button
                    Button {
                        Task {
                            await store.restorePurchases()
                        }
                    } label: {
                        Text("Restore Purchase")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.muted)
                    }
                    .disabled(store.isLoading)

                    // Error message
                    if let error = store.purchaseError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    // Free tier note
                    Text("3 modules free forever: Foundations, Programming Basics, and Data Structures")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.muted)
                }
            }
            .onChange(of: store.isProUnlocked) { _, unlocked in
                if unlocked {
                    dismiss()
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.teal)
            Text(text)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
        }
    }
}

struct LockedModuleOverlay: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("PRO")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange, in: Capsule())
    }
}
