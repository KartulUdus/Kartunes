//
//  IntentHandler.swift
//  KartunesIntentsExtension
//
//  Created by Derek on 10.12.2025.
//

import Intents

/// Main intent handler that routes intents to specific handlers
class IntentHandler: INExtension {
    
    override func handler(for intent: INIntent) -> Any? {
        switch intent {
        case is INPlayMediaIntent:
            return PlayMediaIntentHandler()
        case is INUpdateMediaAffinityIntent:
            return UpdateMediaAffinityIntentHandler()
        default:
            return self
        }
    }
}
