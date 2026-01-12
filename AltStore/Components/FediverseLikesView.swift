//
//  FediverseLikesView.swift
//  AltStore
//
//  Created by Caroline Moore on 1/5/26.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import SwiftUI
import AltStoreCore

struct FediverseLikesView: View
{
    var statusURL: URL
    var statusID: Int
    
    @State
    private var accounts: [MastodonAPI.Account]?
    
    @Environment(\.openURL)
    private var openURL
    
    @Environment(\.dismiss)
    private var dismiss
    
    var body: some View {
        Group {
            if accounts != nil
            {
                listBody
            }
            else
            {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(Text("Likes"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if #available(iOS 26, *)
                {
                    SwiftUI.Button(role: .close) {
                        dismiss()
                    }
                }
                else
                {
                    SwiftUI.Button {
                        openURL(statusURL)
                    } label: {
                        Image(systemName: "globe")
                    }
                    .tint(Color(uiColor: .altPrimary))
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                if #available(iOS 26, *)
                {
                    SwiftUI.Button {
                        openURL(statusURL)
                    } label: {
                        Image(systemName: "globe")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color(uiColor: .altPrimary))
                }
                else
                {
                    SwiftUI.Button("Done") {
                        dismiss()
                    }
                    .tint(Color(uiColor: .altPrimary))
                }
            }
        }
        .task {
            await fetchAccounts()
        }
    }
    
    private var listBody: some View {
        List {
            ForEach(accounts ?? [], id: \.id) { account in
                AccountRow(account: account)
                    .padding(.vertical, 2)
                    .listRowSeparatorTint(.gray.opacity(0.1))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        }
        .listStyle(.plain)
        .overlay {
            if accounts?.isEmpty == true {
                ContentUnavailableView("No Likes Yet", systemImage: "heart")
            }
        }
    }
    
    private func fetchAccounts() async
    {
        do
        {
            let likedBy = try await MastodonAPI.shared.fetchFavorites(tootID: statusID)
            Logger.main.debug("Fetched likes: \(likedBy, privacy: .public)")
            
            self.accounts = likedBy
        }
        catch
        {
            Logger.main.error("Failed to fetch likes for toot. \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct AccountRow: View
{
    var account: MastodonAPI.Account
    
    var body: some View {
        Link(destination: account.url) {
            HStack(alignment: .top, spacing: 15) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: account.avatar_static) { image in
                        image
                            .resizable()
                            .clipShape(Circle())
                    } placeholder: {
                        Circle().fill(Color.gray)
                    }
                    .frame(width: 42, height: 42)
                    
                    // Platform badge
                    if let badge = platformBadge(for: account.url.host) {
                        badge
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                            .background(Circle().fill(.tertiary))
                            .offset(x: 3, y: 2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        let host = account.uri.host()?.lowercased() ?? ""
                        
                        if host == "bsky.brid.gy" || host == "threads.net" || host == "threads.com"
                        {
                            Text("@" + account.username)
                                .foregroundStyle(.primary)
                                .font(.subheadline.bold())
                        }
                        else
                        {
                            Text("@" + account.username)
                                .foregroundStyle(.primary)
                                .font(.subheadline.bold()) +
                            Text("@\(host)")
                                .foregroundStyle(.tertiary)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    
                    Text("^[\(account.followers_count) follower](inflect: true)")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    
                    if let bio = decodePlainTextFromHTML(account.note)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    {
                        Text(bio)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
    
    func platformBadge(for host: String?) -> Image?
    {
        guard let host = host?.lowercased() else { return nil }
        
        switch host
        {
        case "bsky.brid.gy": return Image("BlueskyBadge")
        case "threads.net", "threads.com": return Image("ThreadsBadge")
        default: return Image("MastodonBadge")
        }
    }
    
    func decodePlainTextFromHTML(_ html: String) -> String?
    {
        guard let data = html.data(using: .utf8) else { return nil }
        
        let attributedString = try? NSAttributedString(data: data, options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ], documentAttributes: nil)
        
        return attributedString?.string
    }
}

#Preview {
    FediverseLikesView(statusURL: URL(string: "https://explore.alt.store/@altstore/115738568314750404")!, statusID: 115738568314750404)
}

