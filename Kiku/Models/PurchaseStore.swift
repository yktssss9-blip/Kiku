import Foundation
import RevenueCat
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class PurchaseStore: ObservableObject {
    @Published var isPro: Bool = false {
        didSet {
            guard oldValue != isPro else { return }
            syncProStatusToFirestore()
        }
    }
    @Published var isLoading: Bool = false
    @Published var isOfferingLoading: Bool = true
    @Published var currentOffering: Offering? = nil

    private let db = Firestore.firestore()

    init() {
        isOfferingLoading = true
        Task { await refresh() }
    }

    func refresh() async {
        isOfferingLoading = true
        defer { isOfferingLoading = false }
        do {
            async let infoTask    = Purchases.shared.customerInfo()
            async let offeringTask = Purchases.shared.offerings()
            let (info, offerings) = try await (infoTask, offeringTask)
            isPro           = info.entitlements["Shigodeki Pro"]?.isActive == true
            currentOffering = offerings.current
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

    /// 友達のランキング表示で支配者称号の判定に使えるよう、自分のPro状態を/users/{uid}に書き込む
    private func syncProStatusToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).setData([
            "isPro": isPro
        ], merge: true)
    }
}
