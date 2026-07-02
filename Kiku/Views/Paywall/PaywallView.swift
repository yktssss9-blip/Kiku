import SwiftUI
import RevenueCat

struct PaywallView: View {
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let offering = purchaseStore.currentOffering {
                ProPaywallContent(offering: offering)
            } else if purchaseStore.isOfferingLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                retryView
            }
        }
        .task {
            if purchaseStore.currentOffering == nil && !purchaseStore.isOfferingLoading {
                await purchaseStore.refresh()
            }
        }
    }

    private var retryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("プランを読み込めませんでした")
                .foregroundStyle(.secondary)
            Button("再試行") {
                Task { await purchaseStore.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ProPaywallContent

private struct ProPaywallContent: View {
    let offering: Offering
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPackage: Package?

    private let features: [(String, String)] = [
        ("📤", "テンプレートから質問を送信"),
        ("⚡️", "自動送信スケジュール"),
        ("♾️", "Stop Time 無制限"),
        ("👑", "支配者称号の解放"),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 48)
                    headerSection
                    featuresCard
                    packageSection
                    restoreButton
                    Spacer().frame(height: 96)
                }
                .padding(.horizontal, 20)
            }

            closeButton

            VStack {
                Spacer()
                purchaseButtonBar
            }
        }
        .onAppear {
            selectedPackage = offering.availablePackages
                .first(where: { $0.packageType == .annual })
                ?? offering.availablePackages.first
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        HStack {
            Spacer()
            Button("閉じる") { dismiss() }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Group {
                if let icon = UIImage(named: "AppIcon") {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                } else {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(.label))
                        .frame(width: 88, height: 88)
                        .overlay {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(Color(.systemBackground))
                        }
                }
            }

            Text("Kiku Pro")
                .font(.title.bold())

            Text("コア機能は無料。\nProでもっと便利に、もっと楽しく。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Features Card

    private var featuresCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.offset) { i, feature in
                HStack(spacing: 12) {
                    Text(feature.0)
                        .font(.title3)
                        .frame(width: 32)
                    Text(feature.1)
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if i < features.count - 1 {
                    Divider().padding(.leading, 60)
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Package Selection

    private var packageSection: some View {
        VStack(spacing: 10) {
            ForEach(offering.availablePackages, id: \.identifier) { package in
                PackageCard(
                    package: package,
                    isSelected: selectedPackage?.identifier == package.identifier
                )
                .onTapGesture { selectedPackage = package }
            }
        }
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        Button("購入を復元する") {
            Task {
                try? await purchaseStore.restorePurchases()
                if purchaseStore.isPro { dismiss() }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .disabled(purchaseStore.isLoading)
    }

    // MARK: - Purchase Button Bar

    private var purchaseButtonBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                guard let package = selectedPackage else { return }
                Task {
                    try? await purchaseStore.purchase(package: package)
                    if purchaseStore.isPro { dismiss() }
                }
            } label: {
                Group {
                    if purchaseStore.isLoading {
                        ProgressView().tint(Color(.systemBackground))
                    } else if let pkg = selectedPackage {
                        Text(purchaseLabel(for: pkg))
                    }
                }
                .font(.headline)
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.label), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(purchaseStore.isLoading || selectedPackage == nil)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .background(.regularMaterial)
        }
    }

    private func purchaseLabel(for package: Package) -> String {
        let price = package.localizedPriceString
        let priceText = price.isEmpty ? "" : "（\(price)）"
        return "Proプランにアップグレード\(priceText)"
    }
}

// MARK: - PackageCard

private struct PackageCard: View {
    let package: Package
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(planTitle)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                    if isRecommended {
                        Text("おすすめ")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(isSelected ? Color(.systemBackground).opacity(0.25) : Color.accentColor.opacity(0.15))
                            .foregroundStyle(isSelected ? Color(.systemBackground) : .accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(planDescription)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color(.systemBackground).opacity(0.7) : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(package.localizedPriceString.isEmpty ? "−" : package.localizedPriceString)
                    .font(.title3.bold())
                    .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
                if let period = pricePeriod {
                    Text(period)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color(.systemBackground).opacity(0.7) : .secondary)
                }
            }
        }
        .padding(16)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14).fill(Color(.label))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    }
            }
        }
    }

    private var planTitle: String {
        switch package.packageType {
        case .annual:   return "年額プラン"
        case .monthly:  return "月額プラン"
        case .lifetime: return "買い切り"
        default: return package.storeProduct.localizedTitle
        }
    }

    private var planDescription: String {
        switch package.packageType {
        case .annual:   return "2ヶ月分お得・月換算約408円"
        case .monthly:  return "いつでもキャンセル可能"
        case .lifetime: return "一度の支払いで永久に使える"
        default: return package.storeProduct.localizedDescription
        }
    }

    private var isRecommended: Bool {
        package.packageType == .annual || package.packageType == .lifetime
    }

    private var pricePeriod: String? {
        switch package.packageType {
        case .annual:  return "/年"
        case .monthly: return "/月"
        default: return nil
        }
    }
}
