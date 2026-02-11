//
//  FediverseInteractionsView.swift
//  AltStore
//
//  Created by Riley Testut on 11/19/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import UIKit
import SwiftUI

import AltStoreCore

import NukeUI

@Observable
class FediverseInteractionsView: UIView
{
    var shareHandler: ((URL) -> UIViewController?)?
    
    weak var presentingViewController: UIViewController?
    
    private var contentView: UIView!
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.update(with: nil)
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        self.update(with: nil)
    }
    
    func configure(with item: FederatedItem, isOpaque: Bool = false)
    {
        self.update(with: item, isOpaque: isOpaque)
    }
}

private extension FediverseInteractionsView
{
    func update(with item: FederatedItem?, isOpaque: Bool = false)
    {
        self.contentView?.removeFromSuperview()
        
        let hostingConfiguration = UIHostingConfiguration {
            if let item
            {
                FediverseInteractions(federatedItem: item, isOpaque: isOpaque)
                    .environment(self)
                    .tint(Color(uiColor: self.tintColor))
            }
            else
            {
                EmptyView()
            }
        }.margins(.all, .init(self.directionalLayoutMargins))
        
        self.contentView = hostingConfiguration.makeContentView()
        self.addSubview(self.contentView, pinningEdgesWith: .zero)
    }
}

struct FediverseInteractions: View
{
    @ObservedObject
    var federatedItem: FederatedItem
    
    @State
    var isOpaque: Bool = false
    
    @State
    private var accounts: [SocialWebAccount]?
    
    @State
    private var isShowingLikes = false

    @State
    private var isLiked: Bool = false
    
    @State
    private var likesCount: Int = 0
    
    @State
    private var likesID: UUID = UUID()
    
    @Namespace
    private var unionNamespace
    
    @Environment(FediverseInteractionsView.self)
    private var fediverseInteractionsView
    
    private let preferredHeight: CGFloat = 30
    private let maximumAvatars: Int = 5
    
    private let hapticGenerator = UINotificationFeedbackGenerator()
    
    var body: some View {
        Group {
            HStack {
                // Interactions
                HStack {
                    // Comment + Like buttons
                    socialButtons
                    
                    let avatarSpacing = -(preferredHeight / 2)
                    
                    // Avatars
                    SwiftUI.Button {
                        isShowingLikes = true
                    } label: {
                        HStack(spacing: avatarSpacing) {
                            if let accounts
                            {
                                let accounts = Array(accounts.enumerated().prefix(maximumAvatars)) // We may cache more than the visible number
                                
                                ForEach(accounts, id: \.element) { index, account in
                                    if let avatarURL = account.avatarURL
                                    {
                                        LazyImage(url: account.avatarURL) { state in
                                            if let image = state.image
                                            {
                                                image
                                                    .clipShape(.circle)
                                                    .overlay(Circle().stroke(.tint, lineWidth: 1))
                                                    .frame(width: preferredHeight, height: preferredHeight)
                                            }
                                            else if let error = state.error
                                            {
                                                avatarPlaceholder
                                                    .onAppear {
                                                        Logger.main.error("Failed to fetch Fediverse avatar at \(avatarURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                                                    }
                                            }
                                            else
                                            {
                                                avatarPlaceholder
                                            }
                                        }
                                        .zIndex(Double(-index))
                                    }
                                }
                            }
                            else
                            {
                                let avatarsCount = min(Int(likesCount), maximumAvatars)
                                ForEach(0..<avatarsCount, id: \.self) { _ in
                                    avatarPlaceholder
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                shareButton
            }
            .frame(height: preferredHeight)
            .frame(minWidth: 100, maxWidth: .infinity)
        }
        .task(id: likesID, priority: .medium) { @MainActor in
            do
            {
                let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                
                let _ = try await FederationManager.shared.fetchLikes(for: federatedItem, limit: maximumAvatars * 2, in: context) // Fetch double the amount we need as buffer
                try await context.perform {
                    try context.save()
                }
            }
            catch
            {
                Logger.main.error("Failed to fetch Fediverse interactions for \(String(describing: federatedItem), privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        .sheet(isPresented: $isShowingLikes) {
            NavigationStack {
                FediverseLikesView(federatedItem: federatedItem)
            }
            .presentationDetents([.medium, .large])
        }
        .task(priority: .medium) {
            do
            {
                try await FederationManager.shared.updateInteractions(for: [federatedItem])
            }
            catch
            {
                Logger.main.error("Failed to fetch liked status for \(String(describing: federatedItem), privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        .onAppear {
            isLiked = federatedItem.isLiked
            likesCount = Int(federatedItem.likesCount)
            accounts = federatedItem.likes.compactMap { $0.account }
        }
        .onChange(of: federatedItem.isLiked) { oldValue, newValue in
            isLiked = newValue
        }
        .onChange(of: federatedItem.likesCount) { oldValue, newValue in
            likesCount = Int(newValue)
        }
        .onChange(of: federatedItem._likes) { oldValue, newValue in
            accounts = federatedItem.likes.compactMap { $0.account }
        }
    }
    
    private var socialButtonContent: some View {
        Group {
            // Like button
            SwiftUI.Button {
                like(federatedItem)
            } label: {
                HStack(spacing: 2) {
                    if isLiked
                    {
                        Image(systemName: "heart.fill")
                    }
                    else
                    {
                        Image(systemName: "heart")
                    }
                    
                    if likesCount > 0
                    {
                        Text("\(likesCount)")
                    }
                }
            }
        }
    }
    
    private var socialButtons: some View {
        Group {
            if #available(iOS 26, *)
            {
                GlassEffectContainer(spacing: 0) {
                    if isOpaque
                    {
                        // On opaque background
                        HStack(spacing: -10) {
                            socialButtonContent
                        }
                        
                        .buttonStyle(.glassProminent) // Prominent glass
                        .glassEffectUnion(id: "button", namespace: unionNamespace)
                    }
                    else
                    {
                        // On translucent background
                        HStack(spacing: -10) {
                            socialButtonContent
                        }
                        .buttonStyle(.glass) // Regular glass
                        .glassEffectUnion(id: "button", namespace: unionNamespace)
                    }
                }
                .font(.subheadline)
            }
            else
            {
                HStack(spacing: 12) {
                    if isOpaque
                    {
                        socialButtonContent
                            .foregroundStyle(Color.white)
                    }
                    else
                    {
                        socialButtonContent
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.trailing, 5)
            }
        }
    }
    
    private var shareButton: some View {
        Group {
            if #available(iOS 26, *)
            {
                if isOpaque
                {
                    // On opaque background
                    SwiftUI.Button {
                        shareItem()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .font(.subheadline)
                    .buttonStyle(.glassProminent) // Prominent glass
                    .buttonBorderShape(.circle)
                }
                else
                {
                    // On translucent background
                    SwiftUI.Button {
                        shareItem()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .font(.subheadline)
                    .buttonStyle(.glass) // Regular glass
                    .buttonBorderShape(.circle)
                }
            }
            else
            {
                SwiftUI.Button {
                    shareItem()
                } label: {
                    if isOpaque
                    {
                        Image(systemName: "square.and.arrow.up")
                            .tint(Color.white)
                    }
                    else
                    {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
    
    private var avatarPlaceholder: some View {
        Group {
            if #available(iOS 26, *)
            {
                if isOpaque
                {
                    Circle().fill(.tint)
                        .glassEffect(.clear)
                }
                else
                {
                    Circle().fill(.clear)
                        .glassEffect(.regular)
                }
            }
            else
            {
                Circle().fill(.tint)
                    .stroke(.white.opacity(0.4), lineWidth: 1)
            }
        }
    }
}

private extension FediverseInteractions
{
    func like(_ item: FederatedItem)
    {
        let federatedURL = federatedItem.url
        
        guard let presentingViewController = fediverseInteractionsView.presentingViewController else { return }
        
        Task<Void, Never> {
            let previousState = self.isLiked
            self.isLiked.toggle()
            
            do
            {
                if self.isLiked
                {
                    try await FederationManager.shared.like(item, presentingViewController: presentingViewController)
                }
                else
                {
                    try await FederationManager.shared.unlike(item, presentingViewController: presentingViewController)
                }
                
                self.hapticGenerator.notificationOccurred(.success)
                
                // Re-fetch avatars
                likesID = UUID()
            }
            catch is CancellationError
            {
                // Ignore
                self.isLiked = previousState
            }
            catch
            {
                self.isLiked = previousState
                Logger.main.error("Failed to favorite status \(federatedURL). Error: \(error.localizedDescription, privacy: .public)")
                self.hapticGenerator.notificationOccurred(.error)
                
                let text: String = if item.newsItem != nil {
                    String(localized: "Unable to Like News Alert")
                } else if item.app != nil {
                    String(localized: "Unable to Like App")
                } else if item.appVersion != nil {
                    String(localized: "Unable to Like App Update")
                } else {
                    String(localized: "Unable to Like Item")
                }
                
                let toastView = ToastView(text: text, detailText: error.localizedDescription)
                toastView.show(in: presentingViewController)
            }
        }
    }
    
    func show(_ account: MastodonAPI.Account)
    {
        UIApplication.shared.open(account.url, options: [:])
    }
    
    func shareItem()
    {
        let shareURL = self.federatedItem.newsItem?.shareURL ?? self.federatedItem.app?.shareURL ?? self.federatedItem.appVersion?.shareURL ?? self.federatedItem.url
        guard let presentingViewController = self.fediverseInteractionsView.shareHandler?(shareURL) else { return }
        
        let safariActivity = SafariActivity()
        
        let activityViewController = UIActivityViewController(activityItems: [shareURL], applicationActivities: [safariActivity])
        presentingViewController.present(activityViewController, animated: true)
    }
}
