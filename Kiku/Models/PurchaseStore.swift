import Foundation
import RevenueCat

@MainActor
final class PurchaseStore: ObservableObject {
    @Published var isPro: Bool = false
    @Published var isLoading: Bool = false
    @Published var currentOffering: Offering? = nil

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        do {
            async let infoTask    = Purchases.shared.customerInfo()
            async let offeringTask = Purchases.shared.offerings()
            let (info, offerings) = try await (infoTask, offeringTask)
            isPro            = info.entitlements["Shigodeki Pro"]?.isActive == true
            currentOffering  = offerings.current
        } catch {
            print("[RevenueCat] refresh error: \(error)")
        }
    }

    func purchase(package: Package) async throws {
        isLoading = true
        defer { isLoading = false }
        let result = try await Purchases.shared.purchase(package: package)
        isPro = result.customerInfo.entitlements["Shigodeki Pro"]?.isActive == true
    }

    func restorePurchases() async throws {
        isLoading = true
        defer { isLoading = false }
        let info = try await Purchases.shared.restorePurchases()
        isPro = info.entitlements["Shigodeki Pro"]?.isActive == true
    }
}
