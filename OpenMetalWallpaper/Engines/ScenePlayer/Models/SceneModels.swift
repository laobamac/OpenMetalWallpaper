//
//  SceneModels.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import Foundation
import simd

struct SceneRoot: Codable {
    let general: GeneralSettings?
    let objects: [SceneObject]
}

struct GeneralSettings: Codable {
    let orthogonalprojection: ProjectionSize?
    let fov: Float?
    let perspectiveoverridefov: Float?
    let bloomhdrthreshold: Float?
    let bloomhdrstrength: Float?
    let bloomhdriterations: Int?
}

struct ProjectionSize: Codable {
    let width: Float
    let height: Float
}

struct AnimationLayer: Codable {
    let additive: Bool?
    let animation: Int?
    let blend: Float?
    let id: Int?
    let name: String?
    let rate: Float?
    let visible: BoolOrObject?
}

struct SceneObject: Codable {
    let id: Int?
    let name: String?
    let image: String?
    let type: String?
    let origin: ScriptableValue?
    let size: ScriptableValue?
    let scale: ScriptableValue?
    let angles: ScriptableValue?
    let parent: Int?
    let visible: BoolOrObject?
    let color: ScriptableValue?
    let rawAlpha: ScriptableValue?
    let colorBlendMode: Int?
    let animationlayers: [AnimationLayer]?

    var alpha: Float? {
        return rawAlpha?.floatValue
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case image
        case type
        case origin
        case size
        case scale
        case angles
        case parent
        case visible
        case color
        case rawAlpha = "alpha"
        case colorBlendMode
        case animationlayers
    }

    var isVisible: Bool {
        if let v = visible {
            if case .bool(let b) = v { return b }
            if case .object(let o) = v { return o.value ?? true }
            return true
        }
        return true
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    var intValue: Int?
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

enum ScriptableValue: Codable {
    case string(String)
    case script(value: String)
    case float(Float)
    case int(Int)
    case bool(Bool)
    case floatArray([Float])
    case object([String: ScriptableValue])

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let b = try? container.decode(Bool.self) {
                self = .bool(b)
                return
            }
            if let i = try? container.decode(Int.self) {
                self = .int(i)
                return
            }
            if let f = try? container.decode(Float.self) {
                self = .float(f)
                return
            }
            if let s = try? container.decode(String.self) {
                self = .string(s)
                return
            }
        }
        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var arr: [Float] = []
            while !unkeyedContainer.isAtEnd {
                if let f = try? unkeyedContainer.decode(Float.self) {
                    arr.append(f)
                } else {
                    _ = try? unkeyedContainer.decode(DummyCodable.self)
                }
            }
            self = .floatArray(arr)
            return
        }
        if let container = try? decoder.container(keyedBy: DynamicKey.self) {
            if container.allKeys.count == 1,
                let scriptKey = DynamicKey(stringValue: "value"),
                let val = try? container.decode(String.self, forKey: scriptKey)
            {
                self = .script(value: val)
                return
            }
            var dict: [String: ScriptableValue] = [:]
            for key in container.allKeys {
                if let val = try? container.decode(
                    ScriptableValue.self,
                    forKey: key
                ) {
                    dict[key.stringValue] = val
                }
            }
            self = .object(dict)
            return
        }
        self = .string("0")
    }

    var value: String {
        switch self {
        case .string(let s): return s
        case .script(let v): return v
        case .float(let f): return "\(f)"
        case .int(let i): return "\(i)"
        case .bool(let b): return "\(b)"
        case .floatArray(let a): return a.map { "\($0)" }.joined(separator: " ")
        case .object(let dict):
            if let val = dict["value"] {
                return val.value
            }
            return ""
        }
    }

    var floatValue: Float {
        switch self {
        case .float(let f): return f
        case .int(let i): return Float(i)
        case .string(let s): return Float(s) ?? 0.0
        case .object(let dict):
            if let val = dict["value"] {
                return val.floatValue
            }
            return 0.0
        default: return 0.0
        }
    }

    var float2Value: SIMD2<Float> {
        switch self {
        case .string(let s):
            let parts = s.split(separator: " ").compactMap { Float($0) }
            if parts.count >= 2 { return SIMD2<Float>(parts[0], parts[1]) }
            if parts.count == 1 { return SIMD2<Float>(parts[0], parts[0]) }
            return SIMD2<Float>(0, 0)
        case .floatArray(let a):
            if a.count >= 2 { return SIMD2<Float>(a[0], a[1]) }
            if a.count == 1 { return SIMD2<Float>(a[0], a[0]) }
            return SIMD2<Float>(0, 0)
        case .object(let dict):
            if let val = dict["value"] {
                return val.float2Value
            }
            return SIMD2<Float>(0, 0)
        default: return SIMD2<Float>(0, 0)
        }
    }

    var float3Value: SIMD3<Float> {
        switch self {
        case .string(let s):
            let parts = s.split(separator: " ").compactMap { Float($0) }
            if parts.count >= 3 {
                return SIMD3<Float>(parts[0], parts[1], parts[2])
            }
            if parts.count == 2 { return SIMD3<Float>(parts[0], parts[1], 1.0) }
            if parts.count == 1 {
                return SIMD3<Float>(parts[0], parts[0], parts[0])
            }
            return SIMD3<Float>(0, 0, 0)
        case .floatArray(let a):
            if a.count >= 3 { return SIMD3<Float>(a[0], a[1], a[2]) }
            if a.count == 2 { return SIMD3<Float>(a[0], a[1], 1.0) }
            if a.count == 1 { return SIMD3<Float>(a[0], a[0], a[0]) }
            return SIMD3<Float>(0, 0, 0)
        case .object(let dict):
            if let val = dict["value"] {
                return val.float3Value
            }
            return SIMD3<Float>(0, 0, 0)
        default: return SIMD3<Float>(0, 0, 0)
        }
    }

    var float4Value: SIMD4<Float> {
        switch self {
        case .string(let s):
            let parts = s.split(separator: " ").compactMap { Float($0) }
            if parts.count >= 4 {
                return SIMD4<Float>(parts[0], parts[1], parts[2], parts[3])
            }
            if parts.count == 3 {
                return SIMD4<Float>(parts[0], parts[1], parts[2], 1.0)
            }
            if parts.count == 2 {
                return SIMD4<Float>(parts[0], parts[1], 1.0, 1.0)
            }
            if parts.count == 1 {
                return SIMD4<Float>(parts[0], parts[0], parts[0], 1.0)
            }
            return SIMD4<Float>(0, 0, 0, 1)
        case .floatArray(let a):
            if a.count >= 4 { return SIMD4<Float>(a[0], a[1], a[2], a[3]) }
            if a.count == 3 { return SIMD4<Float>(a[0], a[1], a[2], 1.0) }
            if a.count == 2 { return SIMD4<Float>(a[0], a[1], 1.0, 1.0) }
            if a.count == 1 { return SIMD4<Float>(a[0], a[0], a[0], 1.0) }
            return SIMD4<Float>(0, 0, 0, 1)
        case .object(let dict):
            if let val = dict["value"] {
                return val.float4Value
            }
            return SIMD4<Float>(0, 0, 0, 1)
        default: return SIMD4<Float>(0, 0, 0, 1)
        }
    }

    func encode(to encoder: Encoder) throws {}
}

private struct DummyCodable: Codable {}

enum BoolOrObject: Codable {
    case bool(Bool)
    case object(VisibilityObject)

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
            let b = try? container.decode(Bool.self)
        {
            self = .bool(b)
            return
        }
        if let o = try? VisibilityObject(from: decoder) {
            self = .object(o)
            return
        }
        self = .bool(true)
    }
    func encode(to encoder: Encoder) throws {}
}

struct VisibilityObject: Codable {
    let value: Bool?
}

struct ModelJSON: Codable {
    let material: String?
}

struct MaterialJSON: Codable {
    let passes: [MaterialPass]
}

struct MaterialPass: Codable {
    let textures: [String]
    let shader: String?
    let blending: String?
    let cullmode: String?
    let depthtest: String?
    let depthwrite: String?
}
