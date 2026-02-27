//
//  PuppetRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import MetalKit
import simd

class PuppetRenderable: RenderableObject {
    let device: MTLDevice
    let vertexBuffer: MTLBuffer
    
    // 分层索引缓冲区
    var maskIndexBuffer: MTLBuffer?
    var clippedIndexBuffer: MTLBuffer?
    var overlayIndexBuffer: MTLBuffer?
    var standardIndexBuffer: MTLBuffer?
    
    var maskIndexCount: Int = 0
    var clippedIndexCount: Int = 0
    var overlayIndexCount: Int = 0
    var standardIndexCount: Int = 0

    let uniformBuffer: MTLBuffer
    var boneMatrices: [matrix_float4x4]
    
    let usePixelCoords: Bool
    let skeleton: [PuppetBone]
    let animations: [PuppetAnimation]
    var inverseBindMatrices: [matrix_float4x4] = []
    
    let maskWriteState: MTLDepthStencilState?
    let maskTestState: MTLDepthStencilState?
    
    init(device: MTLDevice, vertices: [PuppetVertex], indices: [UInt32], triangleBones: [Int],
         skeleton: [PuppetBone], animations: [PuppetAnimation],
         position: SIMD3<Float>, rotation: SIMD3<Float>, size: SIMD2<Float>, scale: SIMD3<Float>,
         texture: MTLTexture, effects: [EffectParams], masks: [MTLTexture?], pipeline: MTLRenderPipelineState,
         depthState: MTLDepthStencilState?, maskWriteState: MTLDepthStencilState?, maskTestState: MTLDepthStencilState?, usePixelCoords: Bool) {
        
        self.device = device
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<PuppetVertex>.stride, options: .storageModeShared)!
        
        self.usePixelCoords = usePixelCoords
        self.skeleton = skeleton
        self.animations = animations
        self.maskWriteState = maskWriteState
        self.maskTestState = maskTestState
        
        self.boneMatrices = Array(repeating: matrix_identity_float4x4, count: 100)
        self.uniformBuffer = device.makeBuffer(length: MemoryLayout<matrix_float4x4>.stride * 100, options: .storageModeShared)!
        
        super.init(position: position, rotation: rotation, size: size, scale: scale, texture: texture, effects: effects, masks: masks, pipeline: pipeline, depthState: depthState)
        
        computeInverseBindMatrices()
        setupIndexBuffers(indices: indices, triangleBones: triangleBones)
        
        let ptr = uniformBuffer.contents()
        ptr.copyMemory(from: &boneMatrices, byteCount: MemoryLayout<matrix_float4x4>.stride * 100)
    }
    
    private func setupIndexBuffers(indices: [UInt32], triangleBones: [Int]) {
        var maskBoneIDs = Set<Int>()
        // 自动检测 Blink 动画
        for anim in animations {
            for track in anim.tracks {
                let minScaleY = track.frames.map { $0.s[1] }.min() ?? 1.0
                if minScaleY < 0.2 { maskBoneIDs.insert(track.track_id) }
            }
        }
        
        var jsonClippedIDs = Set<Int>()
        var jsonMaskIDs = Set<Int>()
        for bone in skeleton {
            if let tag = bone.render_tag {
                if tag == "clipped" { jsonClippedIDs.insert(bone.id) }
                else if tag == "mask" { jsonMaskIDs.insert(bone.id) }
            }
        }
        maskBoneIDs.formUnion(jsonMaskIDs)
        
        var maskIndices: [UInt32] = []
        var clippedIndices: [UInt32] = []
        var overlayIndices: [UInt32] = []
        var standardIndices: [UInt32] = []
        
        let hasClippingLogic = !maskBoneIDs.isEmpty || !jsonClippedIDs.isEmpty
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            let boneIdx = (i/3 < triangleBones.count) ? triangleBones[i/3] : -1
            
            if maskBoneIDs.contains(boneIdx) {
                maskIndices.append(indices[i]); maskIndices.append(indices[i+1]); maskIndices.append(indices[i+2])
            } else if jsonClippedIDs.contains(boneIdx) {
                clippedIndices.append(indices[i]); clippedIndices.append(indices[i+1]); clippedIndices.append(indices[i+2])
            } else if hasClippingLogic {
                overlayIndices.append(indices[i]); overlayIndices.append(indices[i+1]); overlayIndices.append(indices[i+2])
            } else {
                standardIndices.append(indices[i]); standardIndices.append(indices[i+1]); standardIndices.append(indices[i+2])
            }
        }
        
        if !maskIndices.isEmpty { maskIndexBuffer = device.makeBuffer(bytes: maskIndices, length: maskIndices.count * 4, options: .storageModeShared); maskIndexCount = maskIndices.count }
        if !clippedIndices.isEmpty { clippedIndexBuffer = device.makeBuffer(bytes: clippedIndices, length: clippedIndices.count * 4, options: .storageModeShared); clippedIndexCount = clippedIndices.count }
        if !overlayIndices.isEmpty { overlayIndexBuffer = device.makeBuffer(bytes: overlayIndices, length: overlayIndices.count * 4, options: .storageModeShared); overlayIndexCount = overlayIndices.count }
        if !standardIndices.isEmpty { standardIndexBuffer = device.makeBuffer(bytes: standardIndices, length: standardIndices.count * 4, options: .storageModeShared); standardIndexCount = standardIndices.count }
    }
    
    func getGlobalBindMatrix(boneIndex: Int, localMatrices: [matrix_float4x4]) -> matrix_float4x4 {
        if boneIndex < 0 || boneIndex >= skeleton.count { return matrix_identity_float4x4 }
        let bone = skeleton[boneIndex]
        let local = localMatrices[boneIndex]
        if bone.parent >= 0 && bone.parent < skeleton.count {
            if bone.parent == boneIndex { return local }
            let parentGlobal = getGlobalBindMatrix(boneIndex: bone.parent, localMatrices: localMatrices)
            return parentGlobal * local
        }
        return local
    }
    
    func computeInverseBindMatrices() {
        inverseBindMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        var localMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        for i in 0..<skeleton.count {
            let m = skeleton[i].matrix
            localMatrices[i] = matrix_float4x4(columns: ( SIMD4<Float>(m[0], m[1], m[2], m[3]), SIMD4<Float>(m[4], m[5], m[6], m[7]), SIMD4<Float>(m[8], m[9], m[10], m[11]), SIMD4<Float>(m[12], m[13], m[14], m[15]) ))
        }
        for i in 0..<skeleton.count {
            let global = getGlobalBindMatrix(boneIndex: i, localMatrices: localMatrices)
            if abs(global.determinant) < 0.000001 { inverseBindMatrices[i] = matrix_identity_float4x4 } else { inverseBindMatrices[i] = global.inverse }
        }
    }
    
    func getGlobalAnimMatrix(boneIndex: Int, localMatrices: [matrix_float4x4], computed: inout [Bool], result: inout [matrix_float4x4]) -> matrix_float4x4 {
        if boneIndex < 0 || boneIndex >= skeleton.count { return matrix_identity_float4x4 }
        if computed[boneIndex] { return result[boneIndex] }
        let bone = skeleton[boneIndex]
        let local = localMatrices[boneIndex]
        var global = local
        if bone.parent >= 0 && bone.parent < skeleton.count && bone.parent != boneIndex {
            let parentGlobal = getGlobalAnimMatrix(boneIndex: bone.parent, localMatrices: localMatrices, computed: &computed, result: &result)
            global = parentGlobal * local
        }
        result[boneIndex] = global
        computed[boneIndex] = true
        return global
    }
    
    func updateAnimation(time: Float) {
        if animations.isEmpty { return }
        let anim = animations[0]
        let fps = anim.fps > 0 ? anim.fps : 30.0
        let duration = Float(anim.length) / fps
        let t = (duration > 0) ? fmod(time, duration) : 0
        let frameIndex = t * fps
        var localMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        
        for i in 0..<skeleton.count {
            let bone = skeleton[i]
            if let track = anim.tracks.first(where: { $0.track_id == bone.id }), !track.frames.isEmpty {
                let totalFrames = track.frames.count
                let idx0 = Int(frameIndex) % totalFrames
                let idx1 = (idx0 + 1) % totalFrames
                let fraction = frameIndex - Float(Int(frameIndex))
                let k1 = track.frames[idx0]
                let k2 = track.frames[idx1]
                let p = mix(SIMD3<Float>(k1.p[0], k1.p[1], k1.p[2]), SIMD3<Float>(k2.p[0], k2.p[1], k2.p[2]), t: fraction)
                let r = mix(SIMD3<Float>(k1.r[0], k1.r[1], k1.r[2]), SIMD3<Float>(k2.r[0], k2.r[1], k2.r[2]), t: fraction)
                let s = mix(SIMD3<Float>(k1.s[0], k1.s[1], k1.s[2]), SIMD3<Float>(k2.s[0], k2.s[1], k2.s[2]), t: fraction)
                let matT = Matrix4x4.translation(x: p.x, y: p.y, z: p.z)
                let matR = Matrix4x4.fromEuler(r)
                let matS = Matrix4x4.scale(x: s.x, y: s.y, z: s.z)
                localMatrices[i] = matT * matR * matS
            } else {
                let m = bone.matrix
                localMatrices[i] = matrix_float4x4(columns: ( SIMD4<Float>(m[0], m[1], m[2], m[3]), SIMD4<Float>(m[4], m[5], m[6], m[7]), SIMD4<Float>(m[8], m[9], m[10], m[11]), SIMD4<Float>(m[12], m[13], m[14], m[15]) ))
            }
        }
        
        var globalComputed = Array(repeating: false, count: skeleton.count)
        var globalMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        for i in 0..<skeleton.count {
            let global = getGlobalAnimMatrix(boneIndex: i, localMatrices: localMatrices, computed: &globalComputed, result: &globalMatrices)
            let skinMatrix = global * inverseBindMatrices[i]
            if i < 100 { boneMatrices[i] = skinMatrix }
        }
        let ptr = uniformBuffer.contents()
        ptr.copyMemory(from: &boneMatrices, byteCount: MemoryLayout<matrix_float4x4>.stride * 100)
    }
    
    override func draw(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(pipeline)
        let geometryScale: matrix_float4x4
        if usePixelCoords { geometryScale = Matrix4x4.scale(x: scale.x, y: scale.y, z: scale.z) } else { geometryScale = Matrix4x4.scale(x: size.x * scale.x, y: size.y * scale.y, z: scale.z) }
        let finalModelMatrix = worldMatrix * geometryScale
        var objUniforms = ObjectUniforms(modelMatrix: finalModelMatrix, alpha: 1.0, color: SIMD4<Float>(1,1,1,1))
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 3)
        encoder.setFragmentBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        
        var count: Int32 = 0
        encoder.setFragmentBytes(&count, length: MemoryLayout<Int32>.size, index: 4)
        encoder.setFragmentTexture(texture, index: 0)
        
        if standardIndexCount > 0, let buf = standardIndexBuffer {
             if let ds = depthState { encoder.setDepthStencilState(ds) }
             encoder.drawIndexedPrimitives(type: .triangle, indexCount: standardIndexCount, indexType: .uint32, indexBuffer: buf, indexBufferOffset: 0)
        } else {
             if maskIndexCount > 0, let buf = maskIndexBuffer, let ws = maskWriteState {
                 encoder.setDepthStencilState(ws)
                 encoder.setStencilReferenceValue(1)
                 encoder.drawIndexedPrimitives(type: .triangle, indexCount: maskIndexCount, indexType: .uint32, indexBuffer: buf, indexBufferOffset: 0)
             }
             if clippedIndexCount > 0, let buf = clippedIndexBuffer, let ts = maskTestState {
                 encoder.setDepthStencilState(ts)
                 encoder.setStencilReferenceValue(1)
                 encoder.drawIndexedPrimitives(type: .triangle, indexCount: clippedIndexCount, indexType: .uint32, indexBuffer: buf, indexBufferOffset: 0)
             }
             if overlayIndexCount > 0, let buf = overlayIndexBuffer, let ds = depthState {
                 encoder.setDepthStencilState(ds)
                 encoder.drawIndexedPrimitives(type: .triangle, indexCount: overlayIndexCount, indexType: .uint32, indexBuffer: buf, indexBufferOffset: 0)
             }
        }
    }
    
    // MARK: - Static Parser Helper
    static func parseOBJ(objContent: String, skinning: [PuppetSkinning]) -> ([PuppetVertex], [UInt32], [Int], Float) {
        var rawPositions: [SIMD3<Float>] = []
        var rawUVs: [SIMD2<Float>] = []
        var finalVertices: [PuppetVertex] = []
        var finalIndices: [UInt32] = []
        var triangleBoneIndices: [Int] = []
        var uniqueVertexMap: [String: UInt32] = [:]
        
        let skinMap = Dictionary(uniqueKeysWithValues: skinning.map { ($0.vertex_id, $0) })
        var minPos = SIMD3<Float>(10000, 10000, 10000)
        var maxPos = SIMD3<Float>(-10000, -10000, -10000)
        
        let lines = objContent.components(separatedBy: .newlines)
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanLine.isEmpty || cleanLine.hasPrefix("#") { continue }
            let parts = cleanLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            if parts[0] == "v" {
                if parts.count >= 4, let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                    let p = SIMD3<Float>(x, y, z)
                    rawPositions.append(p)
                    minPos = simd_min(minPos, p)
                    maxPos = simd_max(maxPos, p)
                }
            } else if parts[0] == "vt" {
                if parts.count >= 3, let u = Float(parts[1]), let v = Float(parts[2]) {
                    rawUVs.append(SIMD2<Float>(u, 1.0 - v))
                }
            } else if parts[0] == "f" {
                var faceIndices: [UInt32] = []
                var dominantBone = -1
                
                for i in 1..<parts.count {
                    let component = parts[i]
                    let subParts = component.components(separatedBy: "/")
                    guard let posIdxRaw = Int(subParts[0]) else { continue }
                    let posIdx = posIdxRaw - 1
                    
                    var uvIdx = 0
                    if subParts.count > 1, let tIdx = Int(subParts[1]) { uvIdx = tIdx - 1 } else { uvIdx = posIdx }
                    
                    let key = "\(posIdx)/\(uvIdx)"
                    
                    if let existingIndex = uniqueVertexMap[key] {
                        faceIndices.append(existingIndex)
                        if dominantBone == -1 {
                             let v = finalVertices[Int(existingIndex)]
                             if v.w1 > 0.5 { dominantBone = Int(v.j1) }
                        }
                    } else {
                        let newIndex = UInt32(finalVertices.count)
                        let position = (posIdx >= 0 && posIdx < rawPositions.count) ? rawPositions[posIdx] : SIMD3<Float>(0,0,0)
                        let texCoord = (uvIdx >= 0 && uvIdx < rawUVs.count) ? rawUVs[uvIdx] : SIMD2<Float>(0,0)
                        
                        var j1: UInt16 = 0, j2: UInt16 = 0, j3: UInt16 = 0, j4: UInt16 = 0
                        var w1: Float = 0, w2: Float = 0, w3: Float = 0, w4: Float = 0
                        
                        if let skin = skinMap[posIdx] {
                            j1 = UInt16(min(skin.bone_indices[0], 99))
                            j2 = UInt16(min(skin.bone_indices[1], 99))
                            j3 = UInt16(min(skin.bone_indices[2], 99))
                            j4 = UInt16(min(skin.bone_indices[3], 99))
                            w1 = skin.weights[0]; w2 = skin.weights[1]; w3 = skin.weights[2]; w4 = skin.weights[3]
                            if dominantBone == -1 && w1 > 0.5 { dominantBone = Int(j1) }
                        }
                        
                        finalVertices.append(PuppetVertex(px: position.x, py: position.y, pz: position.z, u: texCoord.x, v: texCoord.y, j1: j1, j2: j2, j3: j3, j4: j4, w1: w1, w2: w2, w3: w3, w4: w4))
                        uniqueVertexMap[key] = newIndex
                        faceIndices.append(newIndex)
                    }
                }
                
                if faceIndices.count >= 3 {
                    finalIndices.append(faceIndices[0]); finalIndices.append(faceIndices[1]); finalIndices.append(faceIndices[2])
                    triangleBoneIndices.append(dominantBone)
                }
                if faceIndices.count >= 4 {
                    finalIndices.append(faceIndices[0]); finalIndices.append(faceIndices[2]); finalIndices.append(faceIndices[3])
                    triangleBoneIndices.append(dominantBone)
                }
            }
        }
        return (finalVertices, finalIndices, triangleBoneIndices, maxPos.x - minPos.x)
    }
}
