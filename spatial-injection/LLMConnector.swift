//
//  LLMConnector.swift
//  Created for handling communication with the LLM service.
//

import UIKit

final class LLMConnector {
    func send(image: UIImage, spatialContext: String, completion: @escaping (Result<String, Error>) -> Void) {
        // TODO: Implement actual API call to send image and spatial context to LLM
        
        print("Spatial context:", spatialContext)
        
        DispatchQueue.main.async {
            completion(.success("[Mock] LLM response"))
        }
    }
}
