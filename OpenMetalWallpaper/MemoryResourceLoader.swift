/*
 License: AGPLv3
 Author: laobamac
 File: MemoryResourceLoader.swift
 Description: Helper to load video data from RAM for AVPlayer.
*/

import Foundation
import AVFoundation

class MemoryResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    let data: Data
    let contentType: String
    
    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if let contentRequest = loadingRequest.contentInformationRequest {
            contentRequest.contentType = self.contentType
            contentRequest.contentLength = Int64(data.count)
            contentRequest.isByteRangeAccessSupported = true
        }
        
        if let dataRequest = loadingRequest.dataRequest {
            let requestedOffset = Int(dataRequest.requestedOffset)
            let requestedLength = dataRequest.requestedLength
            
            let start = requestedOffset
            let end = min(requestedOffset + requestedLength, data.count)
            
            if start < data.count {
                let subdata = data.subdata(in: start..<end)
                dataRequest.respond(with: subdata)
                loadingRequest.finishLoading()
            }
        }
        
        return true
    }
}
