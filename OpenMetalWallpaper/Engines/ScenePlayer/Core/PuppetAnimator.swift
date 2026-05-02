//
//  PuppetAnimator.swift
//  Renderer
//
//  Created by laobamac on 2026/4/4.
//

import Foundation
import simd

class PuppetAnimator {
    private let skeleton: [PuppetBone]
    private let animations: [PuppetAnimation]
    private let animationLayers: [AnimationLayer]
    private var inverseBindMatrices: [matrix_float4x4] = []
    
    init(skeleton: [PuppetBone], animations: [PuppetAnimation], animationLayers: [AnimationLayer]) {
        self.skeleton = skeleton
        self.animations = animations
        self.animationLayers = animationLayers
        computeInverseBindMatrices()
    }
    
    func computeInverseBindMatrices() {
        inverseBindMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        var localMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        
        for i in 0..<skeleton.count {
            let m = skeleton[i].matrix
            localMatrices[i] = matrix_float4x4(
                columns: (
                    SIMD4<Float>(m[0], m[1], m[2], m[3]),
                    SIMD4<Float>(m[4], m[5], m[6], m[7]),
                    SIMD4<Float>(m[8], m[9], m[10], m[11]),
                    SIMD4<Float>(m[12], m[13], m[14], m[15])
                )
            )
        }
        
        for i in 0..<skeleton.count {
            let global = getGlobalBindMatrix(boneIndex: i, localMatrices: localMatrices)
            if abs(global.determinant) < 0.000001 {
                inverseBindMatrices[i] = matrix_identity_float4x4
            } else {
                inverseBindMatrices[i] = global.inverse
            }
        }
    }
    
    private func getGlobalBindMatrix(boneIndex: Int, localMatrices: [matrix_float4x4]) -> matrix_float4x4 {
        if boneIndex < 0 || boneIndex >= skeleton.count { return matrix_identity_float4x4 }
        let bone = skeleton[boneIndex]
        let local = localMatrices[boneIndex]
        if bone.parent >= 0 && bone.parent < skeleton.count && bone.parent != boneIndex {
            let parentGlobal = getGlobalBindMatrix(boneIndex: bone.parent, localMatrices: localMatrices)
            return parentGlobal * local
        }
        return local
    }
    
    private func getGlobalAnimMatrix(boneIndex: Int, localMatrices: [matrix_float4x4], computed: inout [Bool], result: inout [matrix_float4x4]) -> matrix_float4x4 {
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
    
    func computeBoneMatrices(time: Float) async -> [matrix_float4x4] {
        if animations.isEmpty || skeleton.isEmpty {
            return Array(repeating: matrix_identity_float4x4, count: 100)
        }
        
        var localMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        for i in 0..<skeleton.count {
            let m = skeleton[i].matrix
            localMatrices[i] = matrix_float4x4(
                columns: (
                    SIMD4<Float>(m[0], m[1], m[2], m[3]),
                    SIMD4<Float>(m[4], m[5], m[6], m[7]),
                    SIMD4<Float>(m[8], m[9], m[10], m[11]),
                    SIMD4<Float>(m[12], m[13], m[14], m[15])
                )
            )
        }
        
        let activeLayers = animationLayers.filter { layer in
            if let v = layer.visible {
                if case .bool(let b) = v { return b }
                if case .object(let o) = v { return o.value ?? true }
            }
            return true
        }
        
        for layer in activeLayers {
            guard let animId = layer.animation,
                  let anim = animations.first(where: { $0.id == animId }) else { continue }
            
            let layerRate = layer.rate ?? 1.0
            let layerBlend = layer.blend ?? 1.0
            let fps = anim.fps > 0 ? anim.fps : 30.0
            let duration = Float(anim.length) / fps
            let isPingPong = anim.mode == "ping_pong" || anim.mode == "mirror"
            let isSingle = anim.mode == "single"
            let cycleDuration = isPingPong ? duration * 2.0 : duration
            
            let scaledTime = time * layerRate
            var t: Float = 0.0
            
            if isSingle {
                t = scaledTime
                if t < 0 { t = 0 }
                if t > duration { t = duration }
            } else {
                t = (cycleDuration > 0) ? fmod(scaledTime, cycleDuration) : 0.0
                if t < 0 { t += cycleDuration }
            }
            
            await withTaskGroup(of: (Int, matrix_float4x4?).self) { group in
                for i in 0..<skeleton.count {
                    group.addTask {
                        let bone = self.skeleton[i]
                        guard let track = anim.tracks.first(where: { $0.track_id == bone.id }), !track.frames.isEmpty else {
                            return (i, nil)
                        }
                        
                        let animMat: matrix_float4x4
                        if track.frames.count == 1 {
                            let k1 = track.frames[0]
                            let p = SIMD3<Float>(k1.p[0], k1.p[1], k1.p[2])
                            let r = SIMD3<Float>(k1.r[0], k1.r[1], k1.r[2])
                            let s = SIMD3<Float>(k1.s[0], k1.s[1], k1.s[2])
                            
                            animMat = await Matrix4x4.translation(x: p.x, y: p.y, z: p.z)
                                    * matrix_float4x4(Quaternion.fromEuler(r))
                                    * Matrix4x4.scale(x: s.x, y: s.y, z: s.z)
                        } else {
                            var idx0 = 0
                            var idx1 = 0
                            var fraction: Float = 0.0
                            let firstTime = track.frames[0].time ?? 0.0
                            
                            var localT = t
                            if isPingPong && localT > duration {
                                localT = 2.0 * duration - localT
                                if localT < 0 { localT = 0.0 }
                            }
                            
                            if localT < firstTime {
                                if isPingPong || isSingle {
                                    idx0 = 0
                                    idx1 = 0
                                    fraction = 0.0
                                } else {
                                    idx0 = track.frames.count - 1
                                    idx1 = 0
                                    let t1 = track.frames[idx0].time ?? (Float(idx0) / fps)
                                    let t2 = firstTime + duration
                                    let adjustedT = localT + duration
                                    fraction = (t2 > t1) ? (adjustedT - t1) / (t2 - t1) : 0.0
                                }
                            } else {
                                for j in 0..<track.frames.count {
                                    let fTime = track.frames[j].time ?? (Float(j) / fps)
                                    if fTime <= localT { idx0 = j }
                                }
                                
                                if idx0 >= track.frames.count - 1 {
                                    if isPingPong || isSingle {
                                        idx0 = track.frames.count - 1
                                        idx1 = idx0
                                        fraction = 0.0
                                    } else {
                                        idx1 = 0
                                        let t1 = track.frames[idx0].time ?? (Float(idx0) / fps)
                                        let t2 = duration + firstTime
                                        fraction = (t2 > t1) ? (localT - t1) / (t2 - t1) : 0.0
                                    }
                                } else {
                                    idx1 = idx0 + 1
                                    let t1 = track.frames[idx0].time ?? (Float(idx0) / fps)
                                    let t2 = track.frames[idx1].time ?? (Float(idx1) / fps)
                                    fraction = (t2 > t1) ? (localT - t1) / (t2 - t1) : 0.0
                                }
                            }
                            
                            let k1 = track.frames[idx0]
                            let k2 = track.frames[idx1]
                            
                            let p = mix(
                                SIMD3<Float>(k1.p[0], k1.p[1], k1.p[2]),
                                SIMD3<Float>(k2.p[0], k2.p[1], k2.p[2]),
                                t: fraction
                            )
                            
                            let r1 = SIMD3<Float>(k1.r[0], k1.r[1], k1.r[2])
                            let r2 = SIMD3<Float>(k2.r[0], k2.r[1], k2.r[2])
                            let q1 = await Quaternion.fromEuler(r1)
                            let q2 = await Quaternion.fromEuler(r2)
                            let q = simd_slerp(q1, q2, fraction)
                            
                            let s = mix(
                                SIMD3<Float>(k1.s[0], k1.s[1], k1.s[2]),
                                SIMD3<Float>(k2.s[0], k2.s[1], k2.s[2]),
                                t: fraction
                            )
                            
                            animMat = await Matrix4x4.translation(x: p.x, y: p.y, z: p.z)
                                    * matrix_float4x4(q)
                                    * Matrix4x4.scale(x: s.x, y: s.y, z: s.z)
                        }
                        return (i, animMat)
                    }
                }
                
                for await (index, animMat) in group {
                    if let mat = animMat {
                        let m1 = localMatrices[index]
                        localMatrices[index] = matrix_float4x4(
                            columns: (
                                mix(m1.columns.0, mat.columns.0, t: layerBlend),
                                mix(m1.columns.1, mat.columns.1, t: layerBlend),
                                mix(m1.columns.2, mat.columns.2, t: layerBlend),
                                mix(m1.columns.3, mat.columns.3, t: layerBlend)
                            )
                        )
                    }
                }
            }
        }
        
        var globalComputed = Array(repeating: false, count: skeleton.count)
        var globalMatrices = Array(repeating: matrix_identity_float4x4, count: skeleton.count)
        var boneMatrices = Array(repeating: matrix_identity_float4x4, count: 100)
        
        for i in 0..<skeleton.count {
            let global = getGlobalAnimMatrix(boneIndex: i, localMatrices: localMatrices, computed: &globalComputed, result: &globalMatrices)
            let skinMatrix = global * inverseBindMatrices[i]
            if i < 100 { boneMatrices[i] = skinMatrix }
        }
        
        return boneMatrices
    }
}
