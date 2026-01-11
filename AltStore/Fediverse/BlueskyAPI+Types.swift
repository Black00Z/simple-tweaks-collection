//
//  BlueskyAPI+Types.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

extension BlueskyAPI
{
    struct Account: Decodable
    {
        var did: String
        var handle: String
        var displayName: String?
    }
    
    struct DIDDocument: Decodable
    {
        struct Service: Decodable
        {
            let id: String?
            let type: String
            let serviceEndpoint: String
        }
        
        var id: String
        var service: [Service]?
    }
    
    struct Post: Decodable
    {
        struct Record: Decodable
        {
            var type: String
            var text: String
            var createdAt: Date
            
            var bridgyOriginalUrl: URL?
            var bridgyOriginalText: String?
            
            private enum CodingKeys: String, CodingKey
            {
                case type = "$type"
                case text
                case createdAt
                case bridgyOriginalUrl
                case bridgyOriginalText
            }
        }
        
        struct Viewer: Decodable
        {
            var like: String?
            var bookmarked: Bool?
        }
        
        var uri: String
        var cid: String
        var record: Record
        var viewer: Viewer?
    }
    
    struct FeedResponse: Decodable
    {
        struct FeedItem: Decodable
        {
            var post: Post
        }
        
        var feed: [FeedItem]
        var cursor: String?
    }
        
    struct ErrorResponse: LocalizedError, Decodable
    {
        var errorName: String
        var errorDescription: String?
        
        private enum CodingKeys: String, CodingKey
        {
            case errorName = "error"
            case errorDescription = "message"
        }
    }
}
