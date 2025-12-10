//
//  IntentHandler.swift
//  KartunesIntentsExtension
//
//  Created by Derek on 10.12.2025.
//

import Intents
import Foundation

/// Main intent handler that routes intents to specific handlers
@objc(IntentHandler)
class IntentHandler: INExtension {
    
    private let logger = Log.make(.siri)
    
    override init() {
        super.init()
        // Multiple logging methods to ensure we see something
        NSLog("🔵 IntentHandler: Initialized")
        print("🔵 [SIRI] IntentHandler: Initialized")
        logger.info("IntentHandler initialized")
        
        // Also log bundle info
        if let bundleId = Bundle.main.bundleIdentifier {
            NSLog("🔵 IntentHandler: Bundle ID = \(bundleId)")
            print("🔵 [SIRI] IntentHandler: Bundle ID = \(bundleId)")
        }
        
        // Test CoreData access
        _ = CoreDataStack.shared.viewContext
        NSLog("🔵 IntentHandler: CoreData context accessible")
        print("🔵 [SIRI] IntentHandler: CoreData context accessible")
    }
    
    override func handler(for intent: INIntent) -> Any? {
        let intentType = String(describing: type(of: intent))
        NSLog("🔵 IntentHandler: handler(for:) called with intent: \(intentType)")
        print("🔵 [SIRI] IntentHandler: handler(for:) called with intent: \(intentType)")
        logger.info("IntentHandler.handler(for:) called with intent type: \(intentType)")
        
        switch intent {
        case is INPlayMediaIntent:
            NSLog("🔵 IntentHandler: Returning PlayMediaIntentHandler")
            print("🔵 [SIRI] IntentHandler: Returning PlayMediaIntentHandler")
            logger.info("Returning PlayMediaIntentHandler")
            let handler = PlayMediaIntentHandler()
            NSLog("🔵 IntentHandler: PlayMediaIntentHandler created successfully")
            print("🔵 [SIRI] IntentHandler: PlayMediaIntentHandler created successfully")
            return handler
        case is INUpdateMediaAffinityIntent:
            NSLog("🔵 IntentHandler: Returning UpdateMediaAffinityIntentHandler")
            print("🔵 [SIRI] IntentHandler: Returning UpdateMediaAffinityIntentHandler")
            logger.info("Returning UpdateMediaAffinityIntentHandler")
            let handler = UpdateMediaAffinityIntentHandler()
            NSLog("🔵 IntentHandler: UpdateMediaAffinityIntentHandler created successfully")
            print("🔵 [SIRI] IntentHandler: UpdateMediaAffinityIntentHandler created successfully")
            return handler
        default:
            NSLog("🔵 IntentHandler: Unknown intent type, returning self")
            print("🔵 [SIRI] IntentHandler: Unknown intent type: \(intentType), returning self")
            logger.warning("Unknown intent type: \(intentType)")
            return self
        }
    }
}
