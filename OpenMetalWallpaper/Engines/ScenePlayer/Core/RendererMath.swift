//
//  RendererMath.swift
//  Renderer
//
//  Created by laobamac on 2026/3/13.
//

import Foundation
import simd

struct RendererMath {
    static func makePerspective(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> matrix_float4x4 {
        let ys = 1 / tanf(fovyRadians * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)
        return matrix_float4x4.init(columns: (vector_float4(xs, 0, 0, 0), vector_float4(0, ys, 0, 0), vector_float4(0, 0, zs, -1), vector_float4(0, 0, zs * near, 0)))
    }

    static func makeLookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(z, up))
        let y = cross(x, z)
        let t = SIMD3<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye))
        return matrix_float4x4.init(columns: (vector_float4(x.x, y.x, z.x, 0), vector_float4(x.y, y.y, z.y, 0), vector_float4(x.z, y.z, z.z, 0), vector_float4(t.x, t.y, t.z, 1)))
    }
}
