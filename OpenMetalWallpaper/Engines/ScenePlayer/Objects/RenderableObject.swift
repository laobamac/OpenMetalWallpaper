//
//  RenderableObject.swift
//  Renderer
//
//  Created by laobamac on 2026/1/23.
//

import MetalKit
import simd
import QuartzCore

class RenderableObject {
    var id: Int = -1
    var parentId: Int?
    weak var parent: RenderableObject?

    var localPosition: SIMD3<Float>
    var localRotation: SIMD3<Float>
    var size: SIMD2<Float>
    var scale: SIMD3<Float>
    var alpha: Float

    var texture: MTLTexture
    var frameInfo: [TexFrameInfo]?
    var isVideo: Bool = false
    var currentAnimInfo: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 1)

    let pipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState?

    let vertices: [Float] = [
        -0.5, 0.5, 0, 0, 0,
        -0.5, -0.5, 0, 0, 1,
        0.5, 0.5, 0, 1, 0,
        0.5, -0.5, 0, 1, 1,
    ]

    init(
        position: SIMD3<Float>,
        rotation: SIMD3<Float>,
        size: SIMD2<Float>,
        scale: SIMD3<Float>,
        alpha: Float = 1.0,
        texture: MTLTexture,
        frameInfo: [TexFrameInfo]? = nil,
        isVideo: Bool = false,
        pipeline: MTLRenderPipelineState,
        depthState: MTLDepthStencilState? = nil
    ) {
        self.localPosition = position
        self.localRotation = rotation
        self.size = size
        self.scale = scale
        self.alpha = alpha
        self.texture = texture
        self.frameInfo = frameInfo
        self.isVideo = isVideo
        self.pipeline = pipeline
        self.depthState = depthState
    }

    var worldMatrix: matrix_float4x4 {
        var local = Matrix4x4.translation(
            x: localPosition.x,
            y: localPosition.y,
            z: localPosition.z
        )
        local =
            local
            * Matrix4x4.rotation(
                angle: localRotation.z,
                axis: SIMD3<Float>(0, 0, 1)
            )
        local = local * Matrix4x4.scale(x: scale.x, y: scale.y, z: scale.z)
        if let p = parent { return p.worldMatrix * local }
        return local
    }

    func updateFrame(time: Float) {
        guard let frames = frameInfo, !frames.isEmpty else { return }
        var totalDuration: Float = 0
        for f in frames { totalDuration += f.frametime }
        if totalDuration <= 0 { return }

        var t = fmod(time, totalDuration)
        if t < 0 { t += totalDuration }

        var currentFrame = frames[0]
        for f in frames {
            if t < f.frametime {
                currentFrame = f
                break
            }
            t -= f.frametime
        }

        let tw = Float(texture.width)
        let th = Float(texture.height)
        if tw > 0 && th > 0 {
            let nx = currentFrame.x / tw
            let ny = currentFrame.y / th
            let nw = currentFrame.width / tw
            let nh = currentFrame.height / th
            currentAnimInfo = SIMD4<Float>(nx, ny, nw, nh)
        }
    }

    func update(commandBuffer: MTLCommandBuffer) {
        guard let frames = frameInfo, !frames.isEmpty else { return }
        var totalDuration: Double = 0
        for f in frames { totalDuration += Double(f.frametime) }
        if totalDuration > 0 {
            let t = CACurrentMediaTime().truncatingRemainder(dividingBy: totalDuration)
            updateFrame(time: Float(t))
        }
    }

    func draw(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(pipeline)
        if let ds = depthState { encoder.setDepthStencilState(ds) }

        let geometryScale = Matrix4x4.scale(x: size.x, y: size.y, z: 1)
        let finalModelMatrix = worldMatrix * geometryScale

        var objUniforms = ObjectUniforms(
            modelMatrix: finalModelMatrix,
            alpha: alpha,
            color: SIMD4<Float>(1, 1, 1, 1),
            animInfo: currentAnimInfo
        )

        encoder.setVertexBytes(
            vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            index: 0
        )
        encoder.setVertexBytes(
            &objUniforms,
            length: MemoryLayout<ObjectUniforms>.size,
            index: 2
        )
        encoder.setFragmentBytes(
            &objUniforms,
            length: MemoryLayout<ObjectUniforms>.size,
            index: 2
        )

        encoder.setFragmentTexture(texture, index: 0)

        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
    }

    static func parseTransforms(_ obj: SceneObject) -> (
        SIMD3<Float>, SIMD3<Float>, SIMD2<Float>, SIMD3<Float>
    ) {
        let originStrs = (obj.origin?.value ?? "0 0 0").components(
            separatedBy: " "
        ).compactMap { Float($0) }
        let sizeStrs = (obj.size?.value ?? "100 100").components(
            separatedBy: " "
        ).compactMap { Float($0) }
        let scaleStrs = (obj.scale?.value ?? "1 1 1").components(
            separatedBy: " "
        ).compactMap { Float($0) }
        let angleStrs = (obj.angles?.value ?? "0 0 0").components(
            separatedBy: " "
        ).compactMap { Float($0) }

        var pos = SIMD3<Float>(0, 0, 0)
        if originStrs.count >= 2 {
            pos.x = originStrs[0]
            pos.y = originStrs[1]
        }
        if originStrs.count >= 3 { pos.z = originStrs[2] }

        var size = SIMD2<Float>(100, 100)
        if sizeStrs.count >= 2 {
            size.x = sizeStrs[0]
            size.y = sizeStrs[1]
        }

        var scale = SIMD3<Float>(1, 1, 1)
        if scaleStrs.count >= 2 {
            scale.x = scaleStrs[0]
            scale.y = scaleStrs[1]
        }

        var rotation = SIMD3<Float>(0, 0, 0)
        if angleStrs.count >= 3 {
            rotation.x = angleStrs[0]
            rotation.y = angleStrs[1]
            rotation.z = angleStrs[2]
        }

        return (pos, rotation, size, scale)
    }
}
