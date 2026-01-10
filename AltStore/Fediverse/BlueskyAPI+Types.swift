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
