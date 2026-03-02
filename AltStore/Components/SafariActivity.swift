//
//  SafariActivity.swift
//  AltStore
//
//  Created by Caroline Moore on 2/6/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

class SafariActivity: UIActivity
{
    private var url: URL?
    
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("com.altstore.safari-activity")
    }
    
    override var activityTitle: String? {
        return String(localized: "Open in Browser")
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "safari")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool
    {
        self.url = activityItems.first as? URL
        return self.url != nil
    }
    
    override func perform()
    {
        guard let url else {
            activityDidFinish(false)
            return
        }
        
        UIApplication.shared.open(url, options: [:]) { _ in
            self.activityDidFinish(true)
        }
    }
}
