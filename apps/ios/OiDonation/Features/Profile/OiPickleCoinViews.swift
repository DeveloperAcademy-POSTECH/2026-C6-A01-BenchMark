//
//  OiPickleCoinViews.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import SwiftUI

private struct OiExploreCampusKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable () -> Void)? = nil
}

extension EnvironmentValues {
    var exploreCampusForCoins: (@MainActor @Sendable () -> Void)? {
        get { self[OiExploreCampusKey.self] }
        set { self[OiExploreCampusKey.self] = newValue }
    }
}

/// Figma 6101:8924 / 5400:11811 and the 82.03% MY variant 5903:10546.
struct OiPickleCoinBalance: View {
    let wallet: OiPickleWallet?
    var compact = false
    var showsPlus = true

    private var scale: CGFloat { compact ? 0.8203 : 1 }

    var body: some View {
        HStack(spacing: 10 * scale) {
            if showsPlus {
                Text("+").font(CampusStyle.characterTitle(25 * scale))
                    .dynamicTypeSize(.large)
                    .foregroundStyle(.white).frame(width: 30 * scale, height: 30 * scale)
                    .background(Color(oiRGB: 0xA38C21), in: Circle())
            }
            HStack(spacing: 4 * scale) {
                Image("MYProfileCoin").resizable().scaledToFit()
                    .frame(width: 30 * scale, height: 30 * scale).accessibilityHidden(true)
                Text(wallet?.balanceLabel ?? "—pc")
                    .font(CampusStyle.medium(16 * scale)).tracking(0.32 * scale)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(.black)
            }
        }
        .padding(.leading, 7 * scale).padding(.trailing, 15 * scale).padding(.vertical, 6 * scale)
        .background(Color(oiRGB: 0xFFF9DF), in: Capsule())
        .overlay { Capsule().strokeBorder(Color(oiRGB: 0xA38C21), lineWidth: scale) }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("피클코인")
        .accessibilityValue(wallet.map { $0.unlimited ? "무제한" : "\($0.balance)개" } ?? "잔액 확인 필요")
    }
}

struct OiPickleCoinLink: View {
    let remote: OiRemoteStore?
    var compact = false

    var body: some View {
        NavigationLink {
            if let remote { OiPickleWalletView(remote: remote) }
        } label: {
            OiPickleCoinBalance(wallet: remote?.pickleWallet, compact: compact)
        }
        .buttonStyle(.plain)
        .disabled(remote?.account == nil)
        .accessibilityHint("코인 잔액과 기부 인증, 오이 수집 방법을 확인해요")
        .accessibilityIdentifier("pickle.wallet.open")
    }
}

struct OiPickleWalletView: View {
    let remote: OiRemoteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.exploreCampusForCoins) private var exploreCampus

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                OiCoinScreenHeader(remote: remote, back: { dismiss() })
                VStack(spacing: 20) {
                    NavigationLink { OiCoinEvidenceView(remote: remote) } label: {
                        actionCard("기부 인증 하기")
                    }
                    .disabled(!remote.canVerifyCoinEvidence || remote.needsReauthentication)
                    .accessibilityIdentifier("pickle.wallet.evidence")
                    Button {
                        if let exploreCampus { exploreCampus() } else { dismiss() }
                    } label: { actionCard("오이 수집하러 가기") }
                    .accessibilityIdentifier("pickle.wallet.collect")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                OiCoinWalletStatus(remote: remote).padding(.horizontal, 20)
                Text("처음 가입하면 10pc, POSTECH 기부증서·기부금영수증을 인증하면 30pc를 받아요.\n다른 사람의 오이를 처음 수집할 때마다 1pc를 받아요.")
                    .font(CampusStyle.body(14)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 25)
            }
            .padding(.top, 4).padding(.bottom, 32)
        }
        .background(.white)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: remote.account?.id) { await remote.refreshPickleWallet() }
        .refreshable { await remote.refreshPickleWallet() }
        .accessibilityIdentifier("pickle.wallet")
    }

    private func actionCard(_ title: String) -> some View {
        Text(title).font(CampusStyle.medium(24)).tracking(0.48)
            .foregroundStyle(Color(oiRGB: 0x546930))
            .multilineTextAlignment(.center)
            .padding(20).frame(maxWidth: .infinity, minHeight: 140)
            .background {
                RoundedRectangle(cornerRadius: 30).fill(Color(oiRGB: 0xF1F4EC))
                    .shadow(color: .black.opacity(0.25), radius: 4)
            }
    }
}

struct OiCoinScreenHeader: View {
    let remote: OiRemoteStore
    let back: () -> Void

    var body: some View {
        HStack {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary).frame(width: 50, height: 50)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel("뒤로")
            Spacer(minLength: 16)
            OiPickleCoinBalance(wallet: remote.pickleWallet, showsPlus: false)
        }
        .padding(.horizontal, 20)
    }
}

struct OiCoinWalletStatus: View {
    let remote: OiRemoteStore
    var body: some View {
        VStack(spacing: 8) {
            if remote.isWalletRefreshing { ProgressView("피클코인 확인 중") }
            if let message = remote.walletError {
                Text(message).foregroundStyle(.red)
                Button("잔액 다시 확인") { Task { await remote.refreshPickleWallet() } }
                    .disabled(remote.isWalletRefreshing)
            } else if !remote.coinsEnabled {
                Text("피클코인 기능을 준비 중이에요. 잠시 후 다시 확인해 주세요.")
                    .foregroundStyle(.secondary)
                Button("다시 확인") { Task { await remote.refresh() } }
                    .disabled(remote.isRefreshing)
            }
        }
        .font(CampusStyle.body(14)).multilineTextAlignment(.center)
        .accessibilityIdentifier("pickle.wallet.status")
    }
}

struct OiCoinAwardOverlay: View {
    let remote: OiRemoteStore
    var body: some View {
        Group {
            if let award = remote.coinAward {
                Text("오이 수집 +\(award.amount)pc")
                    .font(CampusStyle.semibold(16)).foregroundStyle(.black)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color(oiRGB: 0xFFF9DF), in: Capsule())
                    .overlay { Capsule().strokeBorder(Color(oiRGB: 0xA38C21), lineWidth: 1) }
                    .padding(.top, 12)
                    .accessibilityIdentifier("pickle.collection.reward")
                    .task(id: award.id) {
                        do { try await Task.sleep(for: .seconds(3)) }
                        catch { return }
                        remote.clearCoinAward(award.id)
                    }
            }
        }
        .allowsHitTesting(false)
    }
}
