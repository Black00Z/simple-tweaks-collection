//
//  FederationManager.swift
//  AltStore
//
//  Created by Riley Testut on 1/8/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

struct FederationManager
{
    static let shared = FederationManager()
        
    private init()
    {
    }
}

extension FederationManager
{
    @MainActor @discardableResult
    func authenticate(presentingViewController: UIViewController) async throws -> SocialWebAccount
    {
        let mastodonAction = UIAlertAction(title: NSLocalizedString("Mastodon", comment: ""), style: .default)
        _ = try await presentingViewController.presentConfirmationAlert(title: NSLocalizedString("Sign in with…", comment: ""), message: "", actions: [mastodonAction])
        
        let account = try await MastodonAPI.shared.authenticate(presentingViewController: presentingViewController)
        Logger.main.info("Authenticated \(account.type.rawValue) account: \(account.name)")
        
        return account
    }
    
    func signOut() async
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        await context.perform {
            do
            {
                let accounts = SocialWebAccount.all(in: context)
                accounts.forEach { context.delete($0) }
                
                try context.save()
            }
            catch
            {
                Logger.main.error("Failed to delete saved social web accounts. \(error.localizedDescription, privacy: .public)")
                
                // Ignore error, it doesn't really matter if this fails.
                // throw error
            }
        }
        
        // Must go AFTER deleting saved social web accounts (or else we'll lose cached account identifier).
        MastodonAPI.shared.signOut()
    }
}
