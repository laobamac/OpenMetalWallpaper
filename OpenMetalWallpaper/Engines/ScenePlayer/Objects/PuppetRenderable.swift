//
//  PuppetRenderable.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import CoreGraphics
import Foundation
import MetalKit
import simd

class PuppetRenderable: RenderableObject {
    let device: MTLDevice
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int

    var uniformBuffers: [MTLBuffer] = []
    var currentBufferIndex: Int = 0
    var boneMatrices: [matrix_float4x4]

    let usePixelCoords: Bool
    let subMeshes: [PuppetSubMesh]?
    let maskBindings: [PuppetMaskBinding]?
    let maskTextures: [MTLTexture]

    let maskWriteState: MTLDepthStencilState?
    let maskTestState: MTLDepthStencilState?
    let puppetMaskPipeline: MTLRenderPipelineState?
    
    private let animator: PuppetAnimator

    init?(
        device: MTLDevice,
        vertices: [PuppetVertex],
        indices: [UInt32],
        subMeshes: [PuppetSubMesh]?,
        maskBindings: [PuppetMaskBinding]?,
        skeleton: [PuppetBone],
        animations: [PuppetAnimation],
        animationLayers: [AnimationLayer],
        position: SIMD3<Float>,
        rotation: SIMD3<Float>,
        size: SIMD2<Float>,
        scale: SIMD3<Float>,
        texture: MTLTexture,
        frameInfo: [TexFrameInfo]?,
        isVideo: Bool,
        maskTextures: [MTLTexture],
        maskWriteState: MTLDepthStencilState?,
        maskTestState: MTLDepthStencilState?,
        puppetMaskPipeline: MTLRenderPipelineState?,
        pipeline: MTLRenderPipelineState,
        depthState: MTLDepthStencilState?,
        usePixelCoords: Bool
    ) {
        self.device = device
        guard
            let vb = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<PuppetVertex>.stride,
                options: .storageModeShared
            )
        else {
            return nil
        }
        self.vertexBuffer = vb

        guard
            let ib = device.makeBuffer(
                bytes: indices,
                length: indices.count * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )
        else {
            return nil
        }
        self.indexBuffer = ib
        self.indexCount = indices.count

        self.usePixelCoords = usePixelCoords
        self.subMeshes = subMeshes
        self.maskBindings = maskBindings
        self.maskTextures = maskTextures
        self.maskWriteState = maskWriteState
        self.maskTestState = maskTestState
        self.puppetMaskPipeline = puppetMaskPipeline
        
        self.boneMatrices = Array(repeating: matrix_identity_float4x4, count: 100)
        
        for _ in 0..<3 {
            guard let ub = device.makeBuffer(
                length: MemoryLayout<matrix_float4x4>.stride * 100,
                options: .storageModeShared
            ) else {
                return nil
            }
            uniformBuffers.append(ub)
        }
        
        self.animator = PuppetAnimator(
            skeleton: skeleton,
            animations: animations,
            animationLayers: animationLayers
        )

        super.init(
            position: position,
            rotation: rotation,
            size: size,
            scale: scale,
            texture: texture,
            frameInfo: frameInfo,
            isVideo: isVideo,
            pipeline: pipeline,
            depthState: depthState
        )
        
        let ptr = uniformBuffers[0].contents()
        ptr.copyMemory(from: &boneMatrices, byteCount: MemoryLayout<matrix_float4x4>.stride * 100)
    }

    func updateAnimation(time: Float) {
        updateFrame(time: time)
        
        Task {
            let matrices = await animator.computeBoneMatrices(time: time)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.boneMatrices = matrices
                self.currentBufferIndex = (self.currentBufferIndex + 1) % self.uniformBuffers.count
                let ptr = self.uniformBuffers[self.currentBufferIndex].contents()
                ptr.copyMemory(
                    from: &self.boneMatrices,
                    byteCount: MemoryLayout<matrix_float4x4>.stride * 100
                )
            }
        }
    }

    override func draw(encoder: MTLRenderCommandEncoder) {
        let geometryScale: matrix_float4x4
        if usePixelCoords {
            geometryScale = Matrix4x4.scale(x: 1.0, y: 1.0, z: 1.0)
        } else {
            geometryScale = Matrix4x4.scale(x: size.x, y: size.y, z: 1.0)
        }
        let finalModelMatrix = worldMatrix * geometryScale
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffers[currentBufferIndex], offset: 0, index: 3)
        
        var objUniforms = ObjectUniforms(
            modelMatrix: finalModelMatrix,
            alpha: alpha,
            color: SIMD4<Float>(1, 1, 1, 1),
            animInfo: currentAnimInfo
        )
        encoder.setVertexBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        encoder.setFragmentBytes(&objUniforms, length: MemoryLayout<ObjectUniforms>.size, index: 2)
        
        let hasMaskLogic = maskBindings != nil && !(maskBindings!.isEmpty) && !maskTextures.isEmpty
        
        if hasMaskLogic, let maskTex = maskTextures.first,
            let maskWrite = maskWriteState, let maskTest = maskTestState,
            let maskPipe = puppetMaskPipeline
        {
            encoder.setRenderPipelineState(maskPipe)
            encoder.setDepthStencilState(maskWrite)
            encoder.setStencilReferenceValue(1)
            encoder.setFragmentTexture(maskTex, index: 0)
            
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indexCount,
                indexType: .uint32,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
            
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            
            if let meshes = subMeshes {
                for (index, mesh) in meshes.enumerated() {
                    if maskBindings!.contains(where: { $0.target_group == index }) {
                        encoder.setDepthStencilState(maskTest)
                        encoder.setStencilReferenceValue(1)
                    } else {
                        if let ds = depthState {
                            encoder.setDepthStencilState(ds)
                        }
                    }
                    encoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: mesh.count,
                        indexType: .uint32,
                        indexBuffer: indexBuffer,
                        indexBufferOffset: mesh.start * MemoryLayout<UInt32>.stride
                    )
                }
            }
        } else {
            encoder.setRenderPipelineState(pipeline)
            if let ds = depthState { encoder.setDepthStencilState(ds) }
            encoder.setFragmentTexture(texture, index: 0)
            
            if let meshes = subMeshes, !meshes.isEmpty {
                for mesh in meshes {
                    encoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: mesh.count,
                        indexType: .uint32,
                        indexBuffer: indexBuffer,
                        indexBufferOffset: mesh.start * MemoryLayout<UInt32>.stride
                    )
                }
            } else {
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: indexCount,
                    indexType: .uint32,
                    indexBuffer: indexBuffer,
                    indexBufferOffset: 0
                )
            }
        }
    }

    static func parseOBJ(objContent: String, skinning: [PuppetSkinning]) -> ([PuppetVertex], [UInt32], Float) {
        var rawPositions: [SIMD3<Float>] = []
        var rawUVs: [SIMD2<Float>] = []
        var finalVertices: [PuppetVertex] = []
        var finalIndices: [UInt32] = []
        var uniqueVertexMap: [String: UInt32] = [:]
        let skinMap = Dictionary(uniqueKeysWithValues: skinning.map { ($0.vertex_id, $0) })
        var minPos = SIMD3<Float>(10000, 10000, 10000)
        var maxPos = SIMD3<Float>(-10000, -10000, -10000)
        
        let lines = objContent.components(separatedBy: .newlines)
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanLine.isEmpty || cleanLine.hasPrefix("#") { continue }
            let parts = cleanLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.isEmpty { continue }
            
            if parts[0] == "v" {
                if parts.count >= 4, let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                    let p = SIMD3<Float>(x, y, z)
                    rawPositions.append(p)
                    minPos = simd_min(minPos, p)
                    maxPos = simd_max(maxPos, p)
                }
            } else if parts[0] == "vt" {
                if parts.count >= 3, let u = Float(parts[1]), let v = Float(parts[2]) {
                    rawUVs.append(SIMD2<Float>(u, v))
                }
            } else if parts[0] == "f" {
                var faceIndices: [UInt32] = []
                for i in 1..<parts.count {
                    let component = parts[i]
                    let subParts = component.components(separatedBy: "/")
                    guard let posIdxRaw = Int(subParts[0]) else { continue }
                    let posIdx = posIdxRaw - 1
                    var uvIdx = 0
                    if subParts.count > 1, let tIdx = Int(subParts[1]) {
                        uvIdx = tIdx - 1
                    } else {
                        uvIdx = posIdx
                    }
                    let key = "\(posIdx)/\(uvIdx)"
                    if let existingIndex = uniqueVertexMap[key] {
                        faceIndices.append(existingIndex)
                    } else {
                        let newIndex = UInt32(finalVertices.count)
                        let position = (posIdx >= 0 && posIdx < rawPositions.count) ? rawPositions[posIdx] : SIMD3<Float>(0, 0, 0)
                        let texCoord = (uvIdx >= 0 && uvIdx < rawUVs.count) ? rawUVs[uvIdx] : SIMD2<Float>(0, 0)
                        var j1: UInt16 = 0, j2: UInt16 = 0, j3: UInt16 = 0, j4: UInt16 = 0
                        var w1: Float = 0, w2: Float = 0, w3: Float = 0, w4: Float = 0
                        if let skin = skinMap[posIdx] {
                            j1 = UInt16(min(skin.bone_indices[0], 99))
                            j2 = UInt16(min(skin.bone_indices[1], 99))
                            j3 = UInt16(min(skin.bone_indices[2], 99))
                            j4 = UInt16(min(skin.bone_indices[3], 99))
                            w1 = skin.weights[0]
                            w2 = skin.weights[1]
                            w3 = skin.weights[2]
                            w4 = skin.weights[3]
                        }
                        finalVertices.append(
                            PuppetVertex(
                                px: position.x, py: position.y, pz: position.z,
                                u: texCoord.x, v: texCoord.y,
                                j1: j1, j2: j2, j3: j3, j4: j4,
                                w1: w1, w2: w2, w3: w3, w4: w4
                            )
                        )
                        uniqueVertexMap[key] = newIndex
                        faceIndices.append(newIndex)
                    }
                }
                if faceIndices.count >= 3 {
                    finalIndices.append(faceIndices[0])
                    finalIndices.append(faceIndices[1])
                    finalIndices.append(faceIndices[2])
                }
                if faceIndices.count >= 4 {
                    finalIndices.append(faceIndices[0])
                    finalIndices.append(faceIndices[2])
                    finalIndices.append(faceIndices[3])
                }
            }
        }
        return (finalVertices, finalIndices, maxPos.x - minPos.x)
    }
}
