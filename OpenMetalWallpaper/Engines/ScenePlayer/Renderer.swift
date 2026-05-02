//
//  Renderer.swift
//  Renderer
//
//  Created by laobamac on 2026/3/13.
//

import AppKit
import Foundation
import MetalKit
import simd

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineManager: PipelineManager
    let sceneLoader: SceneLoader
    weak var targetView: MTKView?

    var sceneContext = SceneContext()
    var startTime: Date = Date()
    var lastTime: TimeInterval = 0
    var isReady: Bool = false
    var isStaticScene: Bool = false

    var hdrTexture: MTLTexture?
    var bloomTextures: [MTLTexture] = []
    var bloomTempTextures: [MTLTexture] = []
    var mousePosition: CGPoint?

    let textureManager: TextureManager

    init?(device: MTLDevice, view: MTKView, textureManager: TextureManager) {
        self.device = device
        self.targetView = view
        self.textureManager = textureManager
        guard let queue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = queue
        self.pipelineManager = PipelineManager(device: device)
        self.sceneLoader = SceneLoader(device: device, pipelineManager: self.pipelineManager, textureManager: textureManager)
        super.init()

        Task {
            do {
                try await pipelineManager.setupPipelines()
                pipelineManager.setupDepthStencilStates()
                await textureManager.setup(device: device)
                self.isReady = true
            } catch {
            }
        }
    }

    func loadScene(folder: URL) async {
        let context = await sceneLoader.loadScene(folder: folder)
        self.sceneContext = context
        self.startTime = Date()
        self.lastTime = 0
        self.checkSceneStaticState()
    }
    
    private func checkSceneStaticState() {
        var hasAnimation = false
        for obj in sceneContext.renderables {
            if obj is PuppetRenderable || obj.isVideo {
                hasAnimation = true
                break
            }
            if let frameInfo = obj.frameInfo, frameInfo.count > 1 {
                hasAnimation = true
                break
            }
        }
        self.isStaticScene = !hasAnimation
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let view = self.targetView else { return }
            if self.isStaticScene {
                view.preferredFramesPerSecond = 30
            } else {
                view.preferredFramesPerSecond = 60
            }
        }
    }

    func updateMousePosition(_ position: CGPoint, in view: NSView) {
        self.mousePosition = position
    }

    func mouseDown(at position: CGPoint, in view: NSView) {
    }

    func mouseUp(at position: CGPoint, in view: NSView) {
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        hdrTexture = device.makeTexture(descriptor: desc)

        bloomTextures.removeAll()
        bloomTempTextures.removeAll()
        
        let targetIterations = min(sceneContext.bloomIterations, 5)
        
        var w = Int(size.width)
        var h = Int(size.height)
        
        if targetIterations > 0 {
            for _ in 0...targetIterations {
                let bDesc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba16Float,
                    width: w,
                    height: h,
                    mipmapped: false
                )
                bDesc.usage = [.renderTarget, .shaderRead]
                if let tex = device.makeTexture(descriptor: bDesc) {
                    bloomTextures.append(tex)
                }
                if let tTex = device.makeTexture(descriptor: bDesc) {
                    bloomTempTextures.append(tTex)
                }
                w = max(1, w / 2)
                h = max(1, h / 2)
            }
        }
    }

    func draw(in view: MTKView) {
        guard isReady, let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let hdrTex = hdrTexture,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let sampler = pipelineManager.samplerState,
              let fPipeline = pipelineManager.finalPipeline else { return }

        let currentTime = Date().timeIntervalSince(startTime)
        lastTime = currentTime
        let time = Float(currentTime)

        for obj in sceneContext.renderables {
            obj.update(commandBuffer: commandBuffer)
        }

        let hdrPassDesc = MTLRenderPassDescriptor()
        hdrPassDesc.colorAttachments[0].texture = hdrTex
        hdrPassDesc.colorAttachments[0].loadAction = .clear
        hdrPassDesc.colorAttachments[0].storeAction = .store
        hdrPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        hdrPassDesc.depthAttachment.texture = descriptor.depthAttachment.texture
        hdrPassDesc.depthAttachment.loadAction = .clear
        hdrPassDesc.depthAttachment.storeAction = .dontCare
        hdrPassDesc.depthAttachment.clearDepth = 1.0
        hdrPassDesc.stencilAttachment.texture = descriptor.stencilAttachment.texture
        hdrPassDesc.stencilAttachment.loadAction = .clear
        hdrPassDesc.stencilAttachment.storeAction = .dontCare
        hdrPassDesc.stencilAttachment.clearStencil = 0

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: hdrPassDesc) else { return }
        encoder.setCullMode(.none)

        let targetAspect = Double(sceneContext.projectionSize.width / sceneContext.projectionSize.height)
        let currentAspect = Double(view.drawableSize.width / view.drawableSize.height)
        var drawWidth = Double(view.drawableSize.width)
        var drawHeight = Double(view.drawableSize.height)
        var vx: Double = 0
        var vy: Double = 0
        if currentAspect > targetAspect {
            drawWidth = Double(view.drawableSize.height) * targetAspect
            vx = (Double(view.drawableSize.width) - drawWidth) / 2
        } else {
            drawHeight = Double(view.drawableSize.width) / targetAspect
            vy = (Double(view.drawableSize.height) - drawHeight) / 2
        }
        encoder.setViewport(MTLViewport(originX: vx, originY: vy, width: drawWidth, height: drawHeight, znear: 0, zfar: 1))

        let fov = sceneContext.currentFOV * (.pi / 180.0)
        let aspect = Float(sceneContext.projectionSize.width / sceneContext.projectionSize.height)
        let camDist = (Float(sceneContext.projectionSize.height) / 2.0) / tan(fov / 2.0)
        let farPlane = max(10000.0, camDist + 10000.0)
        
        let proj = RendererMath.makePerspective(fovyRadians: fov, aspect: aspect, near: 10.0, far: farPlane)
        let viewMat = RendererMath.makeLookAt(
            eye: SIMD3<Float>(Float(sceneContext.projectionSize.width) / 2, Float(sceneContext.projectionSize.height) / 2, -camDist),
            center: SIMD3<Float>(Float(sceneContext.projectionSize.width) / 2, Float(sceneContext.projectionSize.height) / 2, 0),
            up: SIMD3<Float>(0, 1, 0)
        )

        var globals = GlobalUniforms(projectionMatrix: proj, viewMatrix: viewMat, time: time, padding: .zero)
        encoder.setFragmentSamplerState(sampler, index: 0)

        for obj in sceneContext.renderables {
            encoder.setVertexBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
            encoder.setFragmentBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
            if let puppet = obj as? PuppetRenderable {
                puppet.updateAnimation(time: time)
            }
            obj.draw(encoder: encoder)
        }
        encoder.endEncoding()

        if bloomTextures.count > 1 {
            if let extractPipeline = pipelineManager.extractPipeline {
                let extractDesc = MTLRenderPassDescriptor()
                extractDesc.colorAttachments[0].texture = bloomTextures[0]
                extractDesc.colorAttachments[0].loadAction = .dontCare
                if let exEnc = commandBuffer.makeRenderCommandEncoder(descriptor: extractDesc) {
                    exEnc.setRenderPipelineState(extractPipeline)
                    exEnc.setFragmentTexture(hdrTex, index: 0)
                    exEnc.setFragmentSamplerState(sampler, index: 0)
                    var bThreshold = sceneContext.bloomThreshold
                    exEnc.setFragmentBytes(&bThreshold, length: 4, index: 0)
                    exEnc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    exEnc.endEncoding()
                }
            }
            if let blurPipeline = pipelineManager.blurPipeline {
                for i in 0..<bloomTextures.count - 1 {
                    let blurHDesc = MTLRenderPassDescriptor()
                    blurHDesc.colorAttachments[0].texture = bloomTempTextures[i + 1]
                    blurHDesc.colorAttachments[0].loadAction = .dontCare
                    if let encH = commandBuffer.makeRenderCommandEncoder(descriptor: blurHDesc) {
                        var horiz = true
                        encH.setRenderPipelineState(blurPipeline)
                        encH.setFragmentTexture(bloomTextures[i], index: 0)
                        encH.setFragmentSamplerState(sampler, index: 0)
                        encH.setFragmentBytes(&horiz, length: 1, index: 0)
                        encH.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        encH.endEncoding()
                    }
                    let blurVDesc = MTLRenderPassDescriptor()
                    blurVDesc.colorAttachments[0].texture = bloomTextures[i + 1]
                    blurVDesc.colorAttachments[0].loadAction = .dontCare
                    if let encV = commandBuffer.makeRenderCommandEncoder(descriptor: blurVDesc) {
                        var horiz = false
                        encV.setRenderPipelineState(blurPipeline)
                        encV.setFragmentTexture(bloomTempTextures[i + 1], index: 0)
                        encV.setFragmentSamplerState(sampler, index: 0)
                        encV.setFragmentBytes(&horiz, length: 1, index: 0)
                        encV.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        encV.endEncoding()
                    }
                }
            }
            if let upsamplePipeline = pipelineManager.upsamplePipeline, let blurPipeline = pipelineManager.blurPipeline {
                for i in stride(from: bloomTextures.count - 1, to: 0, by: -1) {
                    let upDesc = MTLRenderPassDescriptor()
                    upDesc.colorAttachments[0].texture = bloomTempTextures[i - 1]
                    upDesc.colorAttachments[0].loadAction = .load
                    if let upEnc = commandBuffer.makeRenderCommandEncoder(descriptor: upDesc) {
                        upEnc.setRenderPipelineState(upsamplePipeline)
                        upEnc.setFragmentTexture(bloomTextures[i - 1], index: 0)
                        upEnc.setFragmentTexture(bloomTextures[i], index: 1)
                        upEnc.setFragmentSamplerState(sampler, index: 0)
                        upEnc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        upEnc.endEncoding()
                    }
                    let blurFDesc = MTLRenderPassDescriptor()
                    blurFDesc.colorAttachments[0].texture = bloomTextures[i - 1]
                    blurFDesc.colorAttachments[0].loadAction = .dontCare
                    if let fEnc = commandBuffer.makeRenderCommandEncoder(descriptor: blurFDesc) {
                        var horiz = true
                        fEnc.setRenderPipelineState(blurPipeline)
                        fEnc.setFragmentTexture(bloomTempTextures[i - 1], index: 0)
                        fEnc.setFragmentSamplerState(sampler, index: 0)
                        fEnc.setFragmentBytes(&horiz, length: 1, index: 0)
                        fEnc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        fEnc.endEncoding()
                    }
                }
            }
        }

        if let finalEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            finalEncoder.setRenderPipelineState(fPipeline)
            finalEncoder.setFragmentTexture(hdrTex, index: 0)
            if !bloomTextures.isEmpty {
                finalEncoder.setFragmentTexture(bloomTextures[0], index: 1)
            }
            finalEncoder.setFragmentSamplerState(sampler, index: 0)
            var bStrength = sceneContext.bloomStrength
            var isHDR = sceneContext.isHDREnabled
            finalEncoder.setFragmentBytes(&bStrength, length: 4, index: 0)
            finalEncoder.setFragmentBytes(&isHDR, length: 1, index: 1)
            finalEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            finalEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
