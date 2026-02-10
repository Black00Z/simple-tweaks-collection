//
//  FederatedItem.swift
//  AltStoreCore
//
//  Created by Riley Testut on 1/12/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

@objc(FederatedItem)
public class FederatedItem: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged public var identifier: String
    @NSManaged public var date: Date
    
    @NSManaged public var uri: URL
    @NSManaged public var url: URL // Web URL
    
    @NSManaged public var resolvedBlueskyID: String?
    @NSManaged public var resolvedBlueskyURL: URL?
    
    // State
    @NSManaged public var likesCount: Int32
    @NSManaged public var boostsCount: Int32
    @NSManaged public var commentsCount: Int32
    
    /* Relationships */
    @NSManaged public var newsItem: NewsItem?
    @NSManaged public var app: StoreApp?
    @NSManaged public var appVersion: AppVersion?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init(identifier: String, date: Date, uri: URL, url: URL, likesCount: Int32 = 0, boostsCount: Int32 = 0, commentsCount: Int32 = 0, context: NSManagedObjectContext)
    {
        super.init(entity: FederatedItem.entity(), insertInto: context)
        
        self.identifier = identifier
        self.date = date
        self.uri = uri
        self.url = url
        
        self.likesCount = likesCount
        self.boostsCount = boostsCount
        self.commentsCount = commentsCount
    }
    
    public class func makePlaceholder(identifier: String, uri: URL, url: URL, in context: NSManagedObjectContext) -> FederatedItem
    {
        let placeholder = FederatedItem(entity: FederatedItem.entity(), insertInto: context)
        placeholder.identifier = identifier
        placeholder.uri = uri
        placeholder.url = url
        
        // Do NOT explicitly set values, use defaults to avoid overwriting existing data.
        // placeholder.likesCount = 0
        // placeholder.boostsCount = 0
        // placeholder.commentsCount = 0
        
        return placeholder
    }
}

public extension FederatedItem
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<FederatedItem>
    {
        return NSFetchRequest<FederatedItem>(entityName: "FederatedItem")
    }
}
