//
//  ShaderTypes.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import simd

struct EffectParams {
    var type: Int32
    var maskIndex: Int32
    var speed: Float
    var scale: Float
    var strength: Float
    var exponent: Float
    var direction: SIMD2<Float>
    var bounds: SIMD2<Float>
    var friction: SIMD2<Float>
    var color: SIMD4<Float>
}

struct ObjectUniforms {
    var modelMatrix: matrix_float4x4
    var alpha: Float
    var color: SIMD4<Float>
    var padding: SIMD4<Float> = .zero
}

struct GlobalUniforms {
    var projectionMatrix: matrix_float4x4
    var viewMatrix: matrix_float4x4
    var time: Float
    
    var brightness: Float
    var contrast: Float
    var saturation: Float
}

struct PuppetVertex {
    var px: Float, py: Float, pz: Float
    var pad1: Float = 0
    var u: Float, v: Float
    var j1: UInt16, j2: UInt16, j3: UInt16, j4: UInt16
    var w1: Float, w2: Float, w3: Float, w4: Float
}
