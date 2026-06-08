//
//  PaywallView.swift
//  PianoAi
//
// 订阅付费页

import StoreKit
import SwiftUI

struct PaywallView: View {

    /// 触发订阅墙的具体曲目，nil 表示从设置/个人页进入
    var triggeredBySong: Song? = nil

    @Environment(AuthSession.self)        private var authSession
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss)              private var dismiss

    @State private var selectedProduct: Product? = nil
    @State private var isPurchasing = false
    @State private var errorMessage: String? = nil
    @State private var isRestoring  = false

    private var navigationTitle: String {
        guard let song = triggeredBySong else { return "解锁全部曲目" }
        return "解锁《\(song.displayTitle)》"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    benefitsSection
                    planSection
                    purchaseButton
                    restoreButton
                    legalText
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                await subscriptionManager.loadProducts()
                if selectedProduct == nil {
                    selectedProduct = subscriptionManager.products.last // default: yearly
                }
            }
            .alert("购买失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: triggeredBySong != nil ? "lock.open.fill" : "music.note.house.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
                .padding(.top, 16)

            if let song = triggeredBySong {
                Text("想弹《\(song.displayTitle)》？")
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                Text("订阅 PianoAi Pro，解锁这首及全部 570+ 首高级曲目")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("无限练琴，无限成长")
                    .font(.title2).bold()
                Text("解锁全部高级曲目，享受完整学习体验")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var benefitsSection: some View {
        VStack(spacing: 12) {
            benefitRow("music.note.list",      .blue,   "所有曲目无限访问",   "包括古典、流行、爵士等全部风格")
            benefitRow("waveform",             .purple, "完整 MIDI 试听",     "随时随地感受旋律")
            benefitRow("chart.line.uptrend.xyaxis", .green, "练习进度追踪",    "查看历史记录和准确率")
            benefitRow("arrow.clockwise.circle", .orange, "持续更新曲库",     "每月新增曲目")
        }
        .padding(16)
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func benefitRow(_ icon: String, _ color: Color, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var planSection: some View {
        VStack(spacing: 10) {
            if subscriptionManager.products.isEmpty {
                ProgressView().padding()
            } else {
                ForEach(subscriptionManager.products, id: \.id) { product in
                    PlanCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id
                    ) {
                        selectedProduct = product
                    }
                }
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            isPurchasing = true
            Task {
                do {
                    try await subscriptionManager.purchase(product, session: authSession)
                    if subscriptionManager.isSubscribed { dismiss() }
                } catch {
                    errorMessage = error.localizedDescription
                }
                isPurchasing = false
            }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(selectedProduct.map { "订阅 \($0.displayPrice)" } ?? "选择方案")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selectedProduct != nil ? Color.blue : Color.gray)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(selectedProduct == nil || isPurchasing)
        .animation(.easeInOut(duration: 0.2), value: isPurchasing)
    }

    private var restoreButton: some View {
        Button {
            isRestoring = true
            Task {
                do {
                    try await subscriptionManager.restorePurchases(session: authSession)
                    if subscriptionManager.isSubscribed { dismiss() }
                } catch {
                    errorMessage = error.localizedDescription
                }
                isRestoring = false
            }
        } label: {
            if isRestoring {
                ProgressView().scaleEffect(0.8)
            } else {
                Text("恢复购买").foregroundStyle(.secondary).font(.subheadline)
            }
        }
        .disabled(isRestoring)
    }

    private var legalText: some View {
        Text("订阅将自动续费，可随时在 App Store 设置中取消。\n订阅后所有高级功能立即可用。")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Plan Card

private struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    let onTap: () -> Void

    private var isYearly: Bool { product.id.contains("yearly") }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "年度订阅" : "月度订阅")
                            .font(.headline)
                        if isYearly {
                            Text("最划算")
                                .font(.caption2).fontWeight(.semibold)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    if isYearly {
                        Text("平均每月 \(yearlyMonthlyPrice)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.title3).fontWeight(.bold)
                    Text(isYearly ? "/年" : "/月")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color(.systemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var yearlyMonthlyPrice: String {
        let monthly = (product.price / 12) as NSDecimalNumber
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = product.priceFormatStyle.locale
        return fmt.string(from: monthly) ?? ""
    }
}
