//
//  BlueskyAPI.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation
import AuthenticationServices

import AltStoreCore

extension BlueskyAPI
{
    private static let baseURL = URL(string: "https://bsky.social")!
}

fileprivate extension BlueskyAPI
{
    struct UserTokens: Decodable
    {
        var accessJwt: String
        var refreshJwt: String
        var did: String
        var handle: String
    }
    
    enum AuthorizationType
    {
        case none
        case user
        case refresh
    }
}

struct BlueskyError: ALTLocalizedError
{
    enum Code: Int, ALTErrorCode, CaseIterable
    {
        typealias Error = BlueskyError
        
        case unknown
        case unauthorized
        case http
        
        case invalidDID
        
        case incorrectCredentials
        case postNotFound
        case personalDataServerNotFound
    }
    
    static func unknown(file: String = #fileID, line: UInt = #line) -> BlueskyError { BlueskyError(code: .unknown, sourceFile: file, sourceLine: line) }
    static func unauthorized(file: String = #fileID, line: UInt = #line) -> BlueskyError { BlueskyError(code: .unauthorized, sourceFile: file, sourceLine: line) }
    static func http(statusCode: Int, file: String = #fileID, line: UInt = #line) -> BlueskyError { BlueskyError(code: .http, statusCode: statusCode, sourceFile: file, sourceLine: line) }
    
    static func invalidDID(_ did: String, file: String = #fileID, line: UInt = #line) -> BlueskyError { BlueskyError(code: .invalidDID, did: did, sourceFile: file, sourceLine: line) }
    static func incorrectCredentials(file: String = #fileID, line: UInt = #line) -> BlueskyError { BlueskyError(code: .incorrectCredentials, sourceFile: file, sourceLine: line) }
    static func postNotFound(file: String = #fileID, line: UInt = #line) -> BlueskyError { BlueskyError(code: .postNotFound, sourceFile: file, sourceLine: line) }
    static func personalDataServerNotFound(file: String = #fileID, line: UInt = #line) -> BlueskyError { BlueskyError(code: .personalDataServerNotFound, sourceFile: file, sourceLine: line) }
    
    let code: Code
    
    var statusCode: Int?
    var did: String?
    
    var errorFailure: String?
    var errorTitle: String?
    
    var sourceFile: String?
    var sourceLine: UInt?
        
    var errorFailureReason: String {
        switch self.code
        {
        case .unknown: return String(localized: "An unknown error occured.")
        case .unauthorized: return String(localized: "This request requires an authenticated user.")
        case .http:
            guard let statusCode else { return String(localized: "An HTTP error occured.") }
            return String(format: String(localized: "HTTP Status Code: %@"), statusCode as NSNumber)
            
        case .invalidDID:
            guard let did else { return String(localized: "The provided DID is invalid.") }
            return String(format: String(localized: "The provided DID %@ is invalid."), did)
            
        case .incorrectCredentials:
            return String(localized: "Incorrect username or password.")
            
        case .postNotFound:
            return String(localized: "The requested post could not be found.")
        
        case .personalDataServerNotFound:
            return String(localized: "The Personal Data Server for this user could not be found.")
        }
    }
}

struct BlueskyAPI
{
    static let shared = BlueskyAPI()
    
    private let session = URLSession(configuration: .default)
    
    private init()
    {
    }
}

extension BlueskyAPI
{
    @MainActor
    func authenticate(presentingViewController: UIViewController) async throws -> SocialWebAccount
    {
        let alertController = UIAlertController(title: String(localized: "Sign in with your Bluesky account."), message: String(localized: "You'll need to generate an app-specific password in your Bluesky settings."), preferredStyle: .alert)
        
        alertController.addTextField { textField in
            textField.placeholder = String(localized: "Username")
            textField.textContentType = .username
            textField.keyboardType = .default
            textField.autocorrectionType = .no
            textField.enablesReturnKeyAutomatically = true
        }
        
        alertController.addTextField { textField in
            textField.placeholder = String(localized: "Password")
            textField.textContentType = .password
            textField.keyboardType = .default
            textField.autocorrectionType = .no
            textField.enablesReturnKeyAutomatically = true
            textField.isSecureTextEntry = true
        }
        
        let usernameTextField = alertController.textFields![0]
        let passwordTextField = alertController.textFields![1]
        
        try await withCheckedThrowingContinuation { continuation in
            let signInAction = UIAlertAction(title: String(localized: "Sign in"), style: .default) { _ in
                continuation.resume()
            }
            alertController.addAction(signInAction)
            
            let cancelAction = UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
                continuation.resume(throwing: CancellationError())
            }
            alertController.addAction(cancelAction)
            
            presentingViewController.present(alertController, animated: true)
        }
        
        let username = usernameTextField.text ?? ""
        let password = passwordTextField.text ?? ""
        
        let did = try await self.resolveHandle(username)
        let pdsURL = try await self.resolvePDS(did: did)
        
        try await self.logIn(username: username, password: password, pdsURL: pdsURL)
        
        let account = try await self.fetchAccount(did: did, pdsURL: pdsURL)
        let accountURL = URL(string: "https://bsky.app/profile/\(account.handle)")!
        guard let host = pdsURL.host else { throw BlueskyError.unknown() }
        
        Keychain.shared.socialWebAccountID = account.did
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        try await context.perform {
            _ = SocialWebAccount(name: account.displayName ?? "", username: account.handle, identifier: account.did, url: accountURL, domain: host, type: .bluesky, context: context)
            try context.save()
        }
        
        guard let socialWebAccount = DatabaseManager.shared.socialWebAccount() else { throw BlueskyError.unknown() }
        return socialWebAccount
    }
    
    func signOut()
    {
        Keychain.shared.blueskyAccessToken = nil
        Keychain.shared.blueskyRefreshToken = nil
        Keychain.shared.socialWebAccountID = nil
    }
}

extension BlueskyAPI
{
    func isTootLiked(tootID: Int, tootURL: URL) async throws -> Bool
    {
        guard let post = try await self.bridgedPost(forTootAtURL: tootURL) else { throw BlueskyError.postNotFound() }
        
        let isLiked = (post.viewer?.like != nil)
        return isLiked
    }
    
    func like(tootID: String, tootURL: URL) async throws
    {
        guard let post = try await self.bridgedPost(forTootAtURL: tootURL) else { throw BlueskyError.postNotFound() }
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let (did, domain) = try await context.perform {
            guard let socialWebAccount = DatabaseManager.shared.socialWebAccount(in: context) else { throw BlueskyError.unauthorized() }
            return (socialWebAccount.identifier, socialWebAccount.domain)
        }
                
        guard let requestURL = URL(string: "https://\(domain)/xrpc/com.atproto.repo.createRecord") else { throw BlueskyError.unknown() } // Invalid account
               
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let requestBody = CreateRecordRequest(repo: did, collection: "app.bsky.feed.like", record: .init(createdAt: .now, subject: .init(uri: post.uri, cid: post.cid)))
        
        let bodyData = try encoder.encode(requestBody)
        request.httpBody = bodyData
        
        struct Response: Decodable
        {
            var uri: String
            var cid: String
        }
        
        let _: Response = try await self.send(request, authorizationType: .user)
    }
    
    func unlike(tootID: String, tootURL: URL) async throws
    {
        guard let post = try await self.bridgedPost(forTootAtURL: tootURL) else { throw BlueskyError.postNotFound() }
        
        guard let likeLink = post.viewer?.like else { return } // Not an error, the status is already unliked so just return.
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let (did, domain) = try await context.perform {
            guard let socialWebAccount = DatabaseManager.shared.socialWebAccount(in: context) else { throw BlueskyError.unauthorized() }
            return (socialWebAccount.identifier, socialWebAccount.domain)
        }
        
        let pdsURL = URL(string: "https://\(domain)")!
        let rkey = (likeLink as NSString).lastPathComponent
                
        let requestURL = pdsURL.appending(path: "/xrpc/com.atproto.repo.deleteRecord")
        
        let requestBody = DeleteRecordRequest(repo: did, collection: "app.bsky.feed.like", rkey: rkey)
        let bodyData = try JSONEncoder().encode(requestBody)
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        let _: EmptyResponse = try await self.send(request, authorizationType: .user)
    }
}

private extension BlueskyAPI
{
    func resolveHandle(_ handle: String) async throws -> String
    {
        var components = URLComponents(string: "/xrpc/com.atproto.identity.resolveHandle")!
        components.queryItems = [
            URLQueryItem(name: "handle", value: handle),
        ]
        
        let requestURL = components.url(relativeTo: BlueskyAPI.baseURL)!
        let request = URLRequest(url: requestURL)
        
        struct Response: Decodable
        {
            var did: String
        }
        
        let response: Response = try await self.send(request, authorizationType: .none)
        return response.did
    }
    
    func resolvePDS(did: String) async throws -> URL
    {
        let requestURL: URL
        
        if did.hasPrefix("did:plc:")
        {
            requestURL = URL(string: "https://plc.directory/\(did)")!
        }
        else if let range = did.range(of: "did:web:"), range.lowerBound == did.startIndex
        {
            let domain = [range.upperBound...]
            requestURL = URL(string: "https://\(domain)/.well-known/did.json")!
        }
        else
        {
            throw BlueskyError.invalidDID(did)
        }
        
        let request = URLRequest(url: requestURL)
        let response: DIDDocument = try await self.send(request, authorizationType: .none)
        
        guard let service = response.service?.first(where: { $0.type == "AtprotoPersonalDataServer" }), let pdsURL = URL(string: service.serviceEndpoint) else { throw BlueskyError.personalDataServerNotFound() }
        return pdsURL
    }
    
    func logIn(username: String, password: String, pdsURL: URL) async throws
    {
        let requestURL = pdsURL.appendingPathComponent("/xrpc/com.atproto.server.createSession")
        
        struct Request: Encodable
        {
            var identifier: String
            var password: String
        }
        
        let body = Request(identifier: username, password: password)
        let bodyData = try JSONEncoder().encode(body)
        
        var request = URLRequest(url: requestURL)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = bodyData
        
        do
        {
            let response: UserTokens = try await self.send(request, authorizationType: .none)
            Keychain.shared.blueskyAccessToken = response.accessJwt
            Keychain.shared.blueskyRefreshToken = response.refreshJwt
        }
        catch ~BlueskyError.Code.unauthorized
        {
            throw BlueskyError.incorrectCredentials()
        }
    }
    
    func fetchAccount(did: String, pdsURL: URL) async throws -> Account
    {
        var components = URLComponents(string: "/xrpc/app.bsky.actor.getProfile")!
        components.queryItems = [
            URLQueryItem(name: "actor", value: did),
        ]
        
        let requestURL = components.url(relativeTo: pdsURL)!
        let request = URLRequest(url: requestURL)
        
        let account: Account = try await self.send(request, authorizationType: .user)
        return account
    }
    
    func refreshAccessToken() async throws
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let domain = try await context.perform {
            guard let socialWebAccount = DatabaseManager.shared.socialWebAccount(in: context) else { throw BlueskyError.unauthorized() }
            return socialWebAccount.domain
        }
        
        guard let requestURL = URL(string: "https://\(domain)/xrpc/com.atproto.server.refreshSession") else { throw BlueskyError.unknown() }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        
        let response: UserTokens = try await self.send(request, authorizationType: .refresh)
        Keychain.shared.blueskyAccessToken = response.accessJwt
        Keychain.shared.blueskyRefreshToken = response.refreshJwt
    }
    
    func bridgedPost(forTootAtURL tootURL: URL) async throws -> Post?
    {        
        let username = tootURL.pathComponents[1].dropFirst() // Remove @
        
        let blueskyUsername: String
        
        if username == "altstore"
        {
            blueskyUsername = "alt.store"
        }
        else if username == "stikdebug"
        {
            blueskyUsername = "stikdebug.alt.store"
        }
        else
        {
            blueskyUsername = "\(username).alt.store.ap.brid.gy"
        }
        
        let did = try await self.resolveHandle(blueskyUsername)
        let posts = try await self.fetchAccountPosts(did: did)
        
        let bridgedPost = posts.first { $0.record.bridgyOriginalUrl == tootURL }
        return bridgedPost
    }
    
    func fetchAccountPosts(did: String) async throws -> [Post]
    {
        var allPosts: [Post] = []
        var fetchCursor: String?
        
        repeat
        {
            var components = URLComponents(string: "/xrpc/app.bsky.feed.getAuthorFeed")!
            components.queryItems = [
                URLQueryItem(name: "actor", value: did),
                URLQueryItem(name: "filter", value: "posts_no_replies"),
                URLQueryItem(name: "limit", value: "100"),
            ]
            
            if let fetchCursor
            {
                components.queryItems?.append(URLQueryItem(name: "cursor", value: fetchCursor))
            }
            
            let requestURL = components.url(relativeTo: BlueskyAPI.baseURL)!
            let request = URLRequest(url: requestURL)
            
            let response: FeedResponse = try await self.send(request, authorizationType: .user)
            
            let posts = response.feed.map(\.post)
            allPosts.append(contentsOf: posts)
            
            fetchCursor = response.cursor
            
            if response.feed.isEmpty
            {
                // Stop pagination if empty array is returned.
                break
            }
        }
        while (fetchCursor != nil);
        
        return allPosts
    }
}

private extension BlueskyAPI
{
    func send<ResponseType: Decodable>(_ request: URLRequest, authorizationType: AuthorizationType) async throws -> ResponseType
    {
        var request = request
        
        switch authorizationType
        {
        case .none: break
        case .user:
            guard let accessToken = Keychain.shared.blueskyAccessToken else { throw BlueskyError.unauthorized() }
            request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        case .refresh:
            guard let refreshToken = Keychain.shared.blueskyRefreshToken else { throw BlueskyError.unauthorized() }
            request.setValue("Bearer " + refreshToken, forHTTPHeaderField: "Authorization")
        }
        
        let decoder = Foundation.JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        while true
        {
            let (data, urlResponse) = try await self.session.data(for: request)
            guard let httpResponse = urlResponse as? HTTPURLResponse else { throw BlueskyError.unknown() }
            
            switch httpResponse.statusCode
            {
            case 200...299:
                if ResponseType.self is EmptyResponse.Type
                {
                    // Skip decoding for empty responses
                    return EmptyResponse() as! ResponseType
                }
                
                let response = try decoder.decode(ResponseType.self, from: data)
                return response
                
            case 401:
                switch authorizationType
                {
                case .none:
                    throw BlueskyError.unauthorized()
                    
                case .refresh:
                    self.signOut() // If we get 401 error when refreshing tokens, sign out.
                    throw BlueskyError.unauthorized()
                    
                case .user:
                    try await self.refreshAccessToken()
                    continue // Try again
                }
                
            default:
                let response = try decoder.decode(ErrorResponse.self, from: data)
                throw response
            }
        }
    }
}

