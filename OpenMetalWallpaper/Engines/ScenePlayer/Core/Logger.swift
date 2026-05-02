//
//  Logger.swift
//  Renderer
//
//  Created by laobamac on 2026/1/27.
//

import Foundation

struct Logger {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    static func log(_ message: String, level: String = "INFO") {
        print("[\(formatter.string(from: Date()))] [\(level)] \(message)")
    }
    
    static func error(_ message: String) {
        log(message, level: "ERROR")
    }
    
    static func debug(_ message: String) {
        log(message, level: "DEBUG")
    }
}
