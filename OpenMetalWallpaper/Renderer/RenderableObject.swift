//
//  RenderableObject.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import MetalKit
import simd

class RenderableObject {
    var id: Int = -1
    var parentId: Int?
    weak var parent: RenderableObject?
    
    var localPosition: SIMD3<Float>
    var localRotation: SIMD3<Float>
    let size: SIMD2<Float>
    let scale: SIMD3<Float>
    
    let texture: MTLTexture
    let effects: [EffectParams]
    let masks: [MTLTexture?]
    let pipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState?
    
    let vertices: [Float] = [
        -0.5, -0.5, 0, 0, 0,
         0.5, -0.5, 0, 1, 0,
        -0.5,  0.5, 0, 0, 1,
         0.5,  0.5, 0, 1, 1
    ]
    
    init(position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>, texture: MTLTexture, effects: [EffectParams], masks: [MTLTexture?], pipeline: MTLRenderPipelineState, depthState: MTLDepthStencilState? = nil) {
        self.localPosition = position
        self.localRotation = rotation
        self.size = size
        self.scale = scale
        self.texture = texture
        self.effects = effects
        self.masks = masks
        self.pipeline = pipeline
        self.depthState = depthState
    }
    
    var worldMatrix: matrix_float4x4 {
        var local = Matrix4x4.translation(x: localPosition.x, y: localPosition.y, z: localPosition.z)
        local = local * Matrix4x4.rotation(angle: localRotation.z, axis: SIMD3<Float>(0, 0, 1))
        if let p = parent { return p.worldMatrix * local }
        return local
    }
    
    func draw(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(pipeline)
        if let ds = depthState { encoder.setDepthStencilState(ds) }
        
        let geometryScale = Matrix4x4.scale(x: size.x * scale.x, y: size.y * scale.y, z: 1)
        let finalModelMatrix = worldMatrix * geometryScale
        
        var objUniforms = ObjectUniforms(modelMatrix: finalModelMatrix, alpha: 1.0, color: SIMD4<Float>(1,1,1,1))
        
        encoder.setVertexBytes(vertices, length: vertices.count * 4, index: 0)
        encoder.setVertexBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        encoder.setFragmentBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        
        var currentEffects = effects
        var count = Int32(effects.count)
        if count > 0 {
            encoder.setFragmentBytes(&currentEffects, length: MemoryLayout<EffectParams>.size * effects.count, index: 3)
        } else {
             var dummy = EffectParams(type: 0, maskIndex: 0, speed: 0, scale: 0, strength: 0, exponent: 0, direction: .zero, bounds: .zero, friction: .zero, color: .zero)
             encoder.setFragmentBytes(&dummy, length: MemoryLayout<EffectParams>.size, index: 3)
        }
        encoder.setFragmentBytes(&count, length: MemoryLayout<Int32>.size, index: 4)
        
        encoder.setFragmentTexture(texture, index: 0)
        for (i, mask) in masks.enumerated() {
            if i < 8 { encoder.setFragmentTexture(mask, index: 1 + i) }
        }
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    // MARK: - Static Parsing Helpers
    
    static func parseTransforms(_ obj: SceneObject) -> (SIMD3<Float>, SIMD3<Float>, SIMD2<Float>, SIMD3<Float>) {
        let originStrs = (obj.origin?.value ?? "0 0 0").components(separatedBy: " ").compactMap { Float($0) }
        let sizeStrs = (obj.size?.value ?? "100 100").components(separatedBy: " ").compactMap { Float($0) }
        let scaleStrs = (obj.scale?.value ?? "1 1 1").components(separatedBy: " ").compactMap { Float($0) }
        let angleStrs = (obj.angles?.value ?? "0 0 0").components(separatedBy: " ").compactMap { Float($0) }
        
        var pos = SIMD3<Float>(0,0,0)
        if originStrs.count >= 2 { pos.x = originStrs[0]; pos.y = originStrs[1] }
        if originStrs.count >= 3 { pos.z = originStrs[2] }
        
        var size = SIMD2<Float>(100, 100)
        if sizeStrs.count >= 2 { size.x = sizeStrs[0]; size.y = sizeStrs[1] }
        
        var scale = SIMD3<Float>(1,1,1)
        if scaleStrs.count >= 2 { scale.x = scaleStrs[0]; scale.y = scaleStrs[1] }
        
        var rotation = SIMD3<Float>(0,0,0)
        if angleStrs.count >= 3 {
            rotation.x = angleStrs[0] * .pi / 180.0
            rotation.y = angleStrs[1] * .pi / 180.0
            rotation.z = angleStrs[2] * .pi / 180.0
        }
        return (pos, rotation, size, scale)
    }
    
    static func parseEffects(_ obj: SceneObject, base: URL, textureLoader: MTKTextureLoader) -> ([EffectParams], [MTLTexture?]) {
        var effectParams: [EffectParams] = []
        var maskTextures: [MTLTexture?] = []
        
        guard let effects = obj.effects else { return ([], []) }
        
        func resolveTex(path: String) -> URL {
            let direct = base.appendingPathComponent("materials/\(path).png")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            return base.appendingPathComponent("materials/\(URL(fileURLWithPath: path).lastPathComponent).png")
        }
        
        for effect in effects {
            let fileLower = effect.file.lowercased()
            var type: Int32 = 0
            if fileLower.contains("waterwaves") { type = 2 }
            else if fileLower.contains("shake") { type = 3 }
            else if fileLower.contains("scroll") { type = 1 }
            else if fileLower.contains("foliagesway") { type = 4 }
            else if fileLower.contains("waterripple") { type = 5 }
            else if fileLower.contains("pulse") { type = 6 }
            else if fileLower.contains("tint") { type = 7 }
            
            if type == 0 { continue }
            
            if let pass = effect.passes?.first {
                var constants = pass.constantshadervalues ?? [:]
                // Initialize with safe defaults
                var param = EffectParams(type: type, maskIndex: -1, speed: 1, scale: 1, strength: 0.1, exponent: 1, direction: .zero, bounds: .zero, friction: .zero, color: SIMD4<Float>(0,0,0,1))
                
                func getVal(_ key: String) -> Float {
                    if let v = constants[key] {
                        switch v { case .float(let f): return f; case .string(let s): return (Float(s) ?? 0) }
                    }
                    if let v = constants["ui_editor_properties_" + key] {
                        switch v { case .float(let f): return f; case .string(let s): return (Float(s) ?? 0) }
                    }
                    return 0
                }
                
                func getFirstVal(_ keys: [String]) -> Float {
                    for key in keys {
                        let v = getVal(key)
                        if v != 0 { return v }
                        if constants[key] != nil { return v }
                    }
                    return 0
                }
                
                func getVec2(_ key: String) -> SIMD2<Float> {
                    var valStr: String? = nil
                    if let v = constants[key], case .string(let s) = v { valStr = s }
                    else if let v = constants["ui_editor_properties_" + key], case .string(let s) = v { valStr = s }
                    if let s = valStr {
                        let p = s.components(separatedBy: " ").compactMap{Float($0)}
                        if p.count >= 2 { return SIMD2<Float>(p[0], p[1]) }
                    }
                    return .zero
                }
                
                func getColor(_ key: String) -> SIMD4<Float> {
                    var valStr: String? = nil
                    if let v = constants[key], case .string(let s) = v { valStr = s }
                    if let s = valStr {
                        let p = s.components(separatedBy: " ").compactMap{Float($0)}
                        if p.count >= 3 { return SIMD4<Float>(p[0], p[1], p[2], 1) }
                    }
                    return SIMD4<Float>(0,0,0,1)
                }

                if type == 5 {
                    // WaterRipple: Expects [Mask, Normal]
                    var maskPath: String? = nil
                    var normPath: String? = nil
                    if let texs = pass.textures {
                        if texs.count > 1 { maskPath = texs[1] }
                        if texs.count > 2 { normPath = texs[2] }
                    }
                    if let m = maskPath, let n = normPath {
                        let mLower = m.lowercased()
                        let nLower = n.lowercased()
                        if (mLower.contains("norm") && !mLower.contains("mask")) && nLower.contains("mask") {
                            let temp = maskPath; maskPath = normPath; normPath = temp
                        }
                    } else if let m = maskPath, normPath == nil {
                        if m.lowercased().contains("norm") && !m.lowercased().contains("mask") {
                            normPath = maskPath; maskPath = nil
                        }
                    }
                    var maskTex: MTLTexture? = nil; var normTex: MTLTexture? = nil
                    if let p = maskPath { let u = resolveTex(path: p); maskTex = try? textureLoader.newTexture(URL: u, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) }
                    if let p = normPath { let u = resolveTex(path: p); normTex = try? textureLoader.newTexture(URL: u, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) }
                    
                    if let m = maskTex, let n = normTex {
                        maskTextures.append(m); param.maskIndex = Int32(maskTextures.count - 1); maskTextures.append(n)
                    } else if let m = maskTex {
                        maskTextures.append(m); param.maskIndex = Int32(maskTextures.count - 1)
                    } else if let n = normTex {
                        maskTextures.append(n); param.maskIndex = Int32(maskTextures.count) - 2
                    }
                } else if type == 6 {
                    // Pulse: Expects [Noise, Mask]
                    var noisePath: String? = nil
                    var maskPath: String? = nil
                    if let texs = pass.textures {
                        if texs.count > 1 { noisePath = texs[1] }
                        if texs.count > 2 { maskPath = texs[2] }
                    }
                    
                    var noiseTex: MTLTexture? = nil
                    var maskTex: MTLTexture? = nil
                    
                    if let p = noisePath { let u = resolveTex(path: p); noiseTex = try? textureLoader.newTexture(URL: u, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) }
                    if let p = maskPath { let u = resolveTex(path: p); maskTex = try? textureLoader.newTexture(URL: u, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) }
                    
                    if let m = maskTex {
                        if let n = noiseTex {
                            maskTextures.append(n); param.maskIndex = Int32(maskTextures.count - 1); maskTextures.append(m)
                        } else {
                            // FIX: Do NOT reuse mask as noise. Append nil instead.
                            // This stops "drifting artifacts". Noise will be 0 (black).
                            maskTextures.append(nil); param.maskIndex = Int32(maskTextures.count - 1); maskTextures.append(m)
                        }
                    } else {
                        param.maskIndex = -1
                    }
                } else {
                    if let masks = pass.textures, masks.count > 1, let maskPath = masks[1] {
                        let maskURL = resolveTex(path: maskPath)
                        if let maskTex = try? textureLoader.newTexture(URL: maskURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) {
                            maskTextures.append(maskTex)
                            param.maskIndex = Int32(maskTextures.count - 1)
                        }
                    }
                }
                
                if type == 2 { // WaterWave
                    param.speed = getFirstVal(["speed", "animationspeed"])
                    
                    let scaleVal = getVal("scale")
                    if scaleVal == 0 {
                        param.scale = 0
                        param.strength = 0
                    } else {
                        param.scale = scaleVal
                        param.strength = getVal("strength")
                    }
                    
                    let expVal = getVal("exponent")
                    param.exponent = (expVal == 0) ? 1.0 : expVal
                    
                    let dirVal = getVal("direction")
                    param.direction = SIMD2<Float>(sin(dirVal), cos(dirVal))
                } else if type == 1 { // Scroll
                    param.direction = getVec2("speed")
                } else if type == 3 { // Shake
                    param.speed = getVal("speed")
                    param.strength = getVal("strength")
                    param.direction = SIMD2<Float>(0, 1)
                } else if type == 4 { // FoliageSway
                    param.speed = getVal("speeduv")
                    param.strength = getVal("strength")
                    param.scale = getVal("scale")
                    param.exponent = getVal("phase")
                    param.bounds.x = getVal("power")
                    let dirVal = getVal("scrolldirection")
                    param.direction = SIMD2<Float>(sin(dirVal), cos(dirVal))
                } else if type == 5 { // WaterRipple
                    param.speed = getFirstVal(["animationspeed", "speed", "animation_speed"])
                    param.strength = getFirstVal(["ripplestrength", "strength", "amount", "ripple_strength"])
                    param.scale = getFirstVal(["scale", "ripplescale", "ripple_scale"])
                    let dirVal = getFirstVal(["scrolldirection", "direction", "angle"])
                    param.direction = SIMD2<Float>(sin(dirVal), cos(dirVal))
                    param.friction.x = getFirstVal(["scrollspeed"])
                } else if type == 6 { // Pulse
                    param.speed = getVal("noisespeed")
                    param.strength = getFirstVal(["noiseamount", "amount"])
                    param.bounds.x = getVal("amount")
                    param.color = getColor("tinthigh")
                    param.exponent = getVal("phase")
                } else if type == 7 { // Tint
                    param.color = getColor("color")
                    param.strength = getFirstVal(["alpha", "strength"])
                }
                
                effectParams.append(param)
            }
        }
        return (effectParams, maskTextures)
    }
}
