import SwiftUI
import RevenueCat
import RevenueCatUI

struct PaywallView: View {
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let offering = purchaseStore.currentOffering {
            OfferingView(offering: offering)
        } else {
            ProgressView()
                .task { await purchaseStore.refresh() }
        }
    }
}

// MARK: - OfferingView

private struct OfferingView: View {
    let offering: Offering
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    packageList
                    restoreButton
                }
                .padding()
            }
            .navigationTitle("Shigodeki Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("👑")
                .font(.system(size: 64))
            Text("Shigodeki Pro にアップグレード")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("すべての機能をフル活用しましょう")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    private var packageList: some View {
        VStack(spacing: 12) {
            ForEach(offering.availablePackages, id: \.identifier) { package in
                PackageRow(package: package)
            }
        }
    }

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
}

// MARK: - PackageRow

private struct PackageRow: View {
    let package: Package
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            Task {
                try? await purchaseStore.purchase(package: package)
                if purchaseStore.isPro { dismiss() }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.storeProduct.localizedTitle)
                        .font(.headline)
                    Text(package.storeProduct.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(package.localizedPriceString)
                    .font(.headline)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(purchaseStore.isLoading)
    }
}
