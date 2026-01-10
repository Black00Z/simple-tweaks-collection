//
//  MastodonAPI+Types.swift
//  AltStore
//
//  Created by Riley Testut on 7/24/25.
//  Copyright © 2025 Riley Testut. All rights reserved.
//

import Foundation

extension MastodonAPI
{
    struct Toot: Identifiable, Decodable
    {
        var id: String
        
        var created_at: Date
        var url: URL // Web URL
        
        var replies_count: Int
        var reblogs_count: Int
        var favourites_count: Int
        
        var account: Account
    }
    
    struct Account: Identifiable, Hashable, Decodable
    {
        var id: String
        var username: String
        var acct: String
        
        var url: URL
        var uri: URL // Use for domain
        
        var avatar_static: URL
    }
    
    struct AuthResponse: Decodable
    {
        var iss: String
        var sub: String
        var name: String
        var preferred_username: String
        var profile: URL
        var picture: URL
    }
    
    struct ErrorResponse: LocalizedError, Decodable
    {
        var errorName: String
        var errorDescription: String?
        
        private enum CodingKeys: String, CodingKey
        {
            case errorName = "error"
            case errorDescription = "error_description"
        }
    }
}
