import Foundation
import Combine
import StoreKit

/// The one-off "Remove ads" purchase (99p, non-consumable).
@MainActor
final class Store: ObservableObject {
    static let removeAdsID = "com.stevenwilliams.firefightersfitnesstest.removeads"

    @Published private(set) var adsRemoved: Bool
    @Published private(set) var price: String?
    @Published private(set) var busy = false
    @Published var message: String?

    private var product: Product?
    private var updates: Task<Void, Never>?

    init() {
        adsRemoved = UserDefaults.standard.bool(forKey: "adsRemoved")
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await load()
            await refresh()
        }
    }

    func load() async {
        product = try? await Product.products(for: [Self.removeAdsID]).first
        price = product?.displayPrice
    }

    /// Checks what's been bought, so ads stay off after a reinstall or on a new phone.
    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.removeAdsID, t.revocationDate == nil {
                owned = true
            }
        }
        setRemoved(owned)
    }

    func buy() async {
        if product == nil { await load() }
        guard let product else {
            message = "Couldn't reach the App Store. Check your connection and try again."
            return
        }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
                if adsRemoved { message = "Ads removed. Thank you!" }
            case .pending:
                message = "Your purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        message = adsRemoved ? "Purchase restored. Ads removed." : "No previous purchase found for this Apple ID."
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let t) = result else { return }
        if t.productID == Self.removeAdsID { setRemoved(t.revocationDate == nil) }
        await t.finish()
    }

    private func setRemoved(_ value: Bool) {
        adsRemoved = value
        UserDefaults.standard.set(value, forKey: "adsRemoved")
    }
}
