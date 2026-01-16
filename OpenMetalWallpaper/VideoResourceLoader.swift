/*
 License: AGPLv3
 Author: laobamac
 File: VideoResourceLoader.swift
 Description: Handles loading video data from memory to avoid disk I/O loops.
*/

import AVFoundation
import Foundation

class MemoryResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let data: Data
    private let contentType: String
    
    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
        super.init()
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if let contentInformationRequest = loadingRequest.contentInformationRequest {
            contentInformationRequest.contentType = self.contentType
            contentInformationRequest.contentLength = Int64(data.count)
            contentInformationRequest.isByteRangeAccessSupported = true
        }
        
        if let dataRequest = loadingRequest.dataRequest {
            let requestedOffset = Int(dataRequest.requestedOffset)
            let requestedLength = dataRequest.requestedLength
            
            let start = requestedOffset
            let end = min(requestedOffset + requestedLength, data.count)
            
            if start < data.count {
                let subData = data.subdata(in: start..<end)
                dataRequest.respond(with: subData)
                loadingRequest.finishLoading()
            } else {
                loadingRequest.finishLoading(with: NSError(domain: "com.laobamac.omw", code: -1, userInfo: nil))
            }
        }
        
        return true
    }
}
