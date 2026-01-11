//
//  FederationManager.swift
//  AltStore
//
//  Created by Riley Testut on 1/8/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

actor FederationManager
{
    static let shared = FederationManager()
    
    private var fetchIsLikedTasks = [String: (Date, Task<Bool, Error>)]()
        
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
        let blueskyAction = UIAlertAction(title: NSLocalizedString("Bluesky", comment: ""), style: .default)
        
        let selectedAction = try await presentingViewController.presentConfirmationAlert(title: NSLocalizedString("Sign in with…", comment: ""), message: "", actions: [mastodonAction, blueskyAction])
        
        let account: SocialWebAccount
        if selectedAction == mastodonAction
        {
            account = try await MastodonAPI.shared.authenticate(presentingViewController: presentingViewController)
        }
        else if selectedAction == blueskyAction
        {
            account = try await BlueskyAPI.shared.authenticate(presentingViewController: presentingViewController)
        }
        else
        {
            throw CancellationError()
        }
        
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
        await MastodonAPI.shared.signOut()
        BlueskyAPI.shared.signOut()
    }
}

extension FederationManager
{
    func isPostLiked(@AsyncManaged for item: some Federatable) async throws -> Bool
    {
        guard let rawStatusID = await $item.statusID, let statusID = Int(rawStatusID), let federatedURL = await $item.federatedURL else { throw OperationError.unknown() } // Invalid item
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        if let (date, task) = self.fetchIsLikedTasks[rawStatusID], date > Date.now.addingTimeInterval(-5)
        {
            // Avoid creating multiple tasks within 5 seconds for same status.
                        
            let isLiked = try await task.value
            return isLiked
        }
        
        let task = Task<Bool, Error> {
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            let accountType = try await context.perform {
                guard let socialWebAccount = DatabaseManager.shared.socialWebAccount(in: context) else { throw BlueskyError.unauthorized() } // Generic unauthorized error
                return socialWebAccount.type
            }
            
            let isLiked: Bool
            switch accountType
            {
            case .mastodon: isLiked = try await MastodonAPI.shared.isTootFavorited(tootID: statusID, tootURL: federatedURL)
            case .bluesky: isLiked = try await BlueskyAPI.shared.isTootLiked(tootID: statusID, tootURL: federatedURL)
            }
            
            return isLiked
        }
        
        self.fetchIsLikedTasks[rawStatusID] = (.now, task)
        
        let isLiked = try await task.value
        
        Logger.main.debug("Checked liked status for post \(federatedURL) in \(CFAbsoluteTimeGetCurrent() - startTime) seconds.")
        
        return isLiked
    }
    
    func like(@AsyncManaged _ item: Federatable, presentingViewController: UIViewController?) async throws
    {
        do
        {
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            let accountType = try await context.perform {
                guard let socialWebAccount = DatabaseManager.shared.socialWebAccount(in: context) else { throw BlueskyError.unauthorized() }
                return socialWebAccount.type
            }
            
            guard let statusID = await $item.statusID, let federatedURL = await $item.federatedURL else { throw OperationError.unknown() } // Invalid item
            
            switch accountType
            {
            case .mastodon: try await MastodonAPI.shared.favorite(tootID: statusID, tootURL: federatedURL)
            case .bluesky: try await BlueskyAPI.shared.like(tootID: statusID, tootURL: federatedURL)
            }
            
            Logger.main.debug("Successfully liked status at URL \(federatedURL)")
        }
        catch let error as MastodonError where error.code == .unauthorized
        {
            if let presentingViewController
            {
                // Prompt to log in
                try await self.authenticate(presentingViewController: presentingViewController)
            }
            else
            {
                throw MastodonError.unauthorized()
            }
            
            // Try again
            try await self.like(item, presentingViewController: presentingViewController)
        }
        catch let error as BlueskyError where error.code == .unauthorized
        {
            if let presentingViewController
            {
                // Prompt to log in
                try await self.authenticate(presentingViewController: presentingViewController)
            }
            else
            {
                throw BlueskyError.unauthorized()
            }
            
            // Try again
            try await self.like(item, presentingViewController: presentingViewController)
        }
    }
    
    func unlike(@AsyncManaged _ item: Federatable, presentingViewController: UIViewController?) async throws
    {
        do
        {
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            let accountType = try await context.perform {
                guard let socialWebAccount = DatabaseManager.shared.socialWebAccount(in: context) else { throw BlueskyError.unauthorized() }
                return socialWebAccount.type
            }
            
            guard let statusID = await $item.statusID, let federatedURL = await $item.federatedURL else { throw OperationError.unknown() } // Invalid item
            
            switch accountType
            {
            case .mastodon: try await MastodonAPI.shared.unfavorite(tootID: statusID, tootURL: federatedURL)
            case .bluesky: try await BlueskyAPI.shared.unlike(tootID: statusID, tootURL: federatedURL)
            }
            
            Logger.main.debug("Successfully unliked status at URL \(federatedURL)")
        }
        catch let error as MastodonError where error.code == .unauthorized
        {
            if let presentingViewController
            {
                // Prompt to log in
                try await self.authenticate(presentingViewController: presentingViewController)
            }
            else
            {
                throw MastodonError.unauthorized()
            }
            
            // Try again
            try await self.unlike(item, presentingViewController: presentingViewController)
        }
        catch let error as BlueskyError where error.code == .unauthorized
        {
            if let presentingViewController
            {
                // Prompt to log in
                try await self.authenticate(presentingViewController: presentingViewController)
            }
            else
            {
                throw BlueskyError.unauthorized()
            }
            
            // Try again
            try await self.unlike(item, presentingViewController: presentingViewController)
        }
    }
}
