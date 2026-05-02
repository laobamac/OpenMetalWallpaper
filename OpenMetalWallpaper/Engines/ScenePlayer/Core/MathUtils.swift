//
//  MathUtils.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import simd
import Foundation

struct Quaternion: Sendable {
    static func fromEuler(_ euler: SIMD3<Float>) -> simd_quatf {
        let qx = simd_quatf(angle: euler.x, axis: SIMD3<Float>(1, 0, 0))
        let qy = simd_quatf(angle: euler.y, axis: SIMD3<Float>(0, 1, 0))
        let qz = simd_quatf(angle: euler.z, axis: SIMD3<Float>(0, 0, 1))
        return qz * qy * qx
    }
}

struct Matrix4x4: Sendable {
    static func translation(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
        return matrix
    }
    
    static func scale(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.0.x = x
        matrix.columns.1.y = y
        matrix.columns.2.z = z
        return matrix
    }
    
    static func rotation(angle: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
        let q = simd_quatf(angle: angle, axis: simd_normalize(axis))
        return matrix_float4x4(q)
    }
    
    static func rotationMatrix3x3(angle: Float, axis: SIMD3<Float>) -> matrix_float3x3 {
        let q = simd_quatf(angle: angle, axis: simd_normalize(axis))
        return matrix_float3x3(q)
    }
    
    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        
        return matrix_float4x4(columns: (
            SIMD4<Float>(2.0 / rsl, 0, 0, 0),
            SIMD4<Float>(0, 2.0 / tsb, 0, 0),
            SIMD4<Float>(0, 0, 1.0 / (far - near), 0),
            SIMD4<Float>(-ral / rsl, -tab / tsb, -near / (far - near), 1)
        ))
    }
    
    static func fromEuler(_ euler: SIMD3<Float>) -> matrix_float4x4 {
        return matrix_float4x4(Quaternion.fromEuler(euler))
    }
}
