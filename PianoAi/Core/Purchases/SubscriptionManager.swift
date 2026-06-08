//
//  SubscriptionManager.swift
//  PianoAi
//
// StoreKit 2 subscription manager.
// Product IDs must match exactly what's configured in App Store Connect.

import Foundation
import Observation
import StoreKit

@Observable
final class SubscriptionManager {

    static let productIDs: [String] = [
        "com.pianoai.official.subscription.pro.monthly",
        "com.pianoai.official.subscription.pro.yearly",
    ]

    private(set) var products: [Product] = []
    private(set) var isSubscribed: Bool = false
    private(set) var expiresAt: Date?

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = Task { await listenForTransactions() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load products from App Store

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            print("⚠️ StoreKit product load failed: \(error)")
        }
    }

    // MARK: - Check current entitlements (call on app launch / foreground)

    func refreshStatus(session: AuthSession) async {
        var found = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  tx.productType == .autoRenewable,
                  tx.revocationDate == nil else { continue }
            let expired = tx.expirationDate.map { $0 < Date() } ?? true
            if !expired {
                found = true
                expiresAt = tx.expirationDate
                break
            }
        }
        isSubscribed = found
        if !found { expiresAt = nil }

        // Sync status from backend (source of truth for premium content gating)
        await syncStatusFromBackend(session: session)
    }

    // MARK: - Purchase

    enum PurchaseError: LocalizedError {
        case verificationFailed
        var errorDescription: String? { "收据验证失败，请重试" }
    }

    @MainActor
    func purchase(_ product: Product, session: AuthSession) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verificationResult):
            guard case .verified(let tx) = verificationResult else {
                throw PurchaseError.verificationFailed
            }
            await tx.finish()
            isSubscribed = true
            expiresAt = tx.expirationDate
            await verifyWithBackend(jws: verificationResult.jwsRepresentation, session: session)

        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Restore purchases

    func restorePurchases(session: AuthSession) async throws {
        try await AppStore.sync()
        await refreshStatus(session: session)
    }

    // MARK: - Private helpers

    private func syncStatusFromBackend(session: AuthSession) async {
        guard session.isAuthenticated else { return }
        do {
            let status: SubscriptionStatusResponse = try await session.request(.subscriptionStatus)
            isSubscribed = status.isSubscribed
            expiresAt    = status.expiresAt
        } catch {
            print("⚠️ Failed to fetch subscription status: \(error)")
        }
    }

    private func verifyWithBackend(jws: String, session: AuthSession) async {
        do {
            let status: SubscriptionStatusResponse = try await session.request(
                .verifyTransaction(jws)
            )
            isSubscribed = status.isSubscribed
            expiresAt    = status.expiresAt
            print("✅ Subscription verified with backend, expires: \(status.expiresAt?.description ?? "?")")
        } catch {
            print("⚠️ Backend verification failed: \(error)")
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let tx) = result {
                await tx.finish()
                // Trigger a status refresh next time refreshStatus is called
                if tx.revocationDate != nil {
                    isSubscribed = false
                    expiresAt = nil
                }
            }
        }
    }
}
