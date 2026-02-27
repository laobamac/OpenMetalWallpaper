//
//  Renderer.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import MetalKit
import simd
import AppKit

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    var puppetPipelineState: MTLRenderPipelineState!
    var samplerState: MTLSamplerState!
    var repeatSamplerState: MTLSamplerState!
    
    var depthStencilState: MTLDepthStencilState!
    var maskWriteState: MTLDepthStencilState!
    var maskTestState: MTLDepthStencilState!
    
    var textureLoader: MTKTextureLoader
    var baseFolder: URL?
    var renderables: [RenderableObject] = []
    
    var startTime: Date = Date()
    var projectionSize: CGSize = CGSize(width: 1920, height: 1080)
    
    // Controls
    var timeScale: Float = 1.0
    var brightness: Float = 0.0
    var contrast: Float = 1.0
    var saturation: Float = 1.0
    
    // Transform Overrides
    var userScale: Float = 1.0
    var userOffset: SIMD2<Float> = .zero
    var userRotation: Float = 0.0
    
    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)
        super.init()
        
        if !setupPipeline() {
            print("Renderer: Failed to setup pipeline.")
            return nil
        }
    }
    
    func setupPipeline() -> Bool {
        let bundle = Bundle(for: Renderer.self)
        let library = (try? device.makeDefaultLibrary(bundle: bundle)) ?? device.makeDefaultLibrary()
        
        guard let library = library else {
            print("Renderer Error: Could not load default Metal library.")
            return false
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Standard Pipeline"
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3; vertexDescriptor.attributes[0].offset = 0; vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2; vertexDescriptor.attributes[1].offset = 12; vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 20
        descriptor.vertexDescriptor = vertexDescriptor
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Renderer Error: Failed to create standard pipeline: \(error)")
            return false
        }
        
        // Puppet Pipeline setup
        let puppetDesc = MTLRenderPipelineDescriptor()
        puppetDesc.label = "Puppet Pipeline"
        puppetDesc.vertexFunction = library.makeFunction(name: "vertex_puppet")
        puppetDesc.fragmentFunction = library.makeFunction(name: "fragment_main")
        puppetDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        puppetDesc.colorAttachments[0].isBlendingEnabled = true
        puppetDesc.colorAttachments[0].rgbBlendOperation = .add
        puppetDesc.colorAttachments[0].alphaBlendOperation = .add
        puppetDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        puppetDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        puppetDesc.depthAttachmentPixelFormat = .depth32Float_stencil8
        puppetDesc.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        let pvDesc = MTLVertexDescriptor()
        pvDesc.attributes[0].format = .float3; pvDesc.attributes[0].offset = 0; pvDesc.attributes[0].bufferIndex = 0
        pvDesc.attributes[1].format = .float2; pvDesc.attributes[1].offset = 16; pvDesc.attributes[1].bufferIndex = 0
        pvDesc.attributes[2].format = .ushort4; pvDesc.attributes[2].offset = 24; pvDesc.attributes[2].bufferIndex = 0
        pvDesc.attributes[3].format = .float4; pvDesc.attributes[3].offset = 32; pvDesc.attributes[3].bufferIndex = 0
        pvDesc.layouts[0].stride = 48
        puppetDesc.vertexDescriptor = pvDesc
        
        do {
            puppetPipelineState = try device.makeRenderPipelineState(descriptor: puppetDesc)
        } catch {
            print("Renderer Error: Failed to create puppet pipeline: \(error)")
            return false
        }
        
        // Samplers
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear; samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge; samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
        
        let repeatDesc = MTLSamplerDescriptor()
        repeatDesc.minFilter = .linear; repeatDesc.magFilter = .linear
        repeatDesc.sAddressMode = .repeat; repeatDesc.tAddressMode = .repeat
        repeatDesc.normalizedCoordinates = true
        repeatSamplerState = device.makeSamplerState(descriptor: repeatDesc)
        
        setupDepthStencilStates()
        return true
    }
    
    func setupDepthStencilStates() {
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.isDepthWriteEnabled = true
        depthDesc.depthCompareFunction = .lessEqual
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)
        
        let maskWriteDesc = MTLDepthStencilDescriptor()
        maskWriteDesc.isDepthWriteEnabled = false
        maskWriteDesc.depthCompareFunction = .always
        let sw = MTLStencilDescriptor()
        sw.stencilCompareFunction = .always
        sw.stencilFailureOperation = .keep
        sw.depthFailureOperation = .keep
        sw.depthStencilPassOperation = .replace
        sw.readMask = 0xFF; sw.writeMask = 0xFF
        maskWriteDesc.frontFaceStencil = sw; maskWriteDesc.backFaceStencil = sw
        maskWriteState = device.makeDepthStencilState(descriptor: maskWriteDesc)
        
        let maskTestDesc = MTLDepthStencilDescriptor()
        maskTestDesc.isDepthWriteEnabled = true
        maskTestDesc.depthCompareFunction = .lessEqual
        let st = MTLStencilDescriptor()
        st.stencilCompareFunction = .equal
        st.stencilFailureOperation = .keep
        st.depthFailureOperation = .keep
        st.depthStencilPassOperation = .keep
        st.readMask = 0xFF; st.writeMask = 0x00
        maskTestDesc.frontFaceStencil = st; maskTestDesc.backFaceStencil = st
        maskTestState = device.makeDepthStencilState(descriptor: maskTestDesc)
    }
    
    func loadScene(folder: URL) {
        let secured = folder.startAccessingSecurityScopedResource()
        defer { if secured { folder.stopAccessingSecurityScopedResource() } }
        
        self.baseFolder = folder
        renderables.removeAll()
        startTime = Date()
        
        let projectURL = folder.appendingPathComponent("project.json")
        guard FileManager.default.fileExists(atPath: projectURL.path),
              let projData = try? Data(contentsOf: projectURL),
              let projJson = try? JSONSerialization.jsonObject(with: projData, options: []) as? [String: Any],
              let sceneFile = projJson["file"] as? String else {
            return
        }
        
        let sceneURL = folder.appendingPathComponent(sceneFile)
        do {
            let sceneData = try Data(contentsOf: sceneURL)
            let sceneRoot = try JSONDecoder().decode(SceneRoot.self, from: sceneData)
            
            if let proj = sceneRoot.general?.orthogonalprojection {
                self.projectionSize = CGSize(width: Double(proj.width), height: Double(proj.height))
            }
            
            var tempRenderables: [Int: RenderableObject] = [:]
            var orderedList: [RenderableObject] = []
            
            for obj in sceneRoot.objects {
                if !obj.isVisible { continue }
                if let renderable = createRenderable(from: obj) {
                    if let id = obj.id {
                        tempRenderables[id] = renderable
                        renderable.id = id
                    }
                    renderable.parentId = obj.parent
                    orderedList.append(renderable)
                }
            }
            
            for renderable in orderedList {
                if let pid = renderable.parentId, let parentObj = tempRenderables[pid] {
                    renderable.parent = parentObj
                }
            }
            
            self.renderables = orderedList
            
        } catch {
            print("Renderer Error: Scene parse error: \(error)")
        }
    }
    
    func createRenderable(from obj: SceneObject) -> RenderableObject? {
        guard let imagePath = obj.image, let base = baseFolder else { return nil }
        let modelURL = base.appendingPathComponent(imagePath)
        let fileName = modelURL.deletingPathExtension().lastPathComponent
        
        let puppetDataURL = modelURL.deletingLastPathComponent().appendingPathComponent("\(fileName)_puppet_data.json")
        let puppetObjURL = modelURL.deletingLastPathComponent().appendingPathComponent("\(fileName)_puppet.obj")
        
        if FileManager.default.fileExists(atPath: puppetDataURL.path) {
            return createPuppetRenderable(from: obj, dataURL: puppetDataURL, objURL: puppetObjURL)
        }
        
        guard let modelData = try? Data(contentsOf: modelURL),
              let modelDef = try? JSONDecoder().decode(ModelJSON.self, from: modelData),
              let matPath = modelDef.material else { return nil }
        
        let matURL = base.appendingPathComponent(matPath)
        guard let matData = try? Data(contentsOf: matURL),
              let matDef = try? JSONDecoder().decode(MaterialJSON.self, from: matData),
              let firstPass = matDef.passes.first,
              let texName = firstPass.textures.first else { return nil }
        
        let texURL = resolveTextureURL(base: base, rawPath: texName)
        guard let texture = try? textureLoader.newTexture(URL: texURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) else { return nil }
        
        let (pos, rotation, size, scale) = RenderableObject.parseTransforms(obj)
        let (effects, masks) = RenderableObject.parseEffects(obj, base: base, textureLoader: textureLoader)
        
        guard let ps = pipelineState else { return nil }
        
        return RenderableObject(position: pos, rotation: rotation, size: size, scale: scale, texture: texture, effects: effects, masks: masks, pipeline: ps, depthState: depthStencilState)
    }
    
    func createPuppetRenderable(from obj: SceneObject, dataURL: URL, objURL: URL) -> RenderableObject? {
        guard let jsonData = try? Data(contentsOf: dataURL),
              let puppetData = try? JSONDecoder().decode(PuppetData.self, from: jsonData),
              let objContent = try? String(contentsOf: objURL, encoding: .utf8) else { return nil }
        
        guard let matFile = puppetData.info.material_file, let base = baseFolder else { return nil }
        let matURL = base.appendingPathComponent(matFile)
        guard let matData = try? Data(contentsOf: matURL),
              let matDef = try? JSONDecoder().decode(MaterialJSON.self, from: matData),
              let firstPass = matDef.passes.first,
              let texName = firstPass.textures.first else { return nil }
        
        let texURL = resolveTextureURL(base: base, rawPath: texName)
        guard let texture = try? textureLoader.newTexture(URL: texURL, options: [.origin: MTKTextureLoader.Origin.bottomLeft, .SRGB: false]) else { return nil }

        let (vertices, indices, triangleBoneIndices, bboxWidth) = PuppetRenderable.parseOBJ(objContent: objContent, skinning: puppetData.skinning)
        let usePixelCoords = bboxWidth > 2.0
        
        let (pos, rotation, size, scale) = RenderableObject.parseTransforms(obj)
        let (effects, masks) = RenderableObject.parseEffects(obj, base: base, textureLoader: textureLoader)
        
        guard let ps = puppetPipelineState else { return nil }
        
        return PuppetRenderable(
            device: device,
            vertices: vertices,
            indices: indices,
            triangleBones: triangleBoneIndices,
            skeleton: puppetData.skeleton,
            animations: puppetData.animations,
            position: pos,
            rotation: rotation,
            size: size,
            scale: scale,
            texture: texture,
            effects: effects,
            masks: masks,
            pipeline: ps,
            depthState: depthStencilState,
            maskWriteState: maskWriteState,
            maskTestState: maskTestState,
            usePixelCoords: usePixelCoords
        )
    }
    
    func resolveTextureURL(base: URL, rawPath: String) -> URL {
        let extensions = ["png", "jpg", "jpeg", "tga", "bmp"]
        let fileName = URL(fileURLWithPath: rawPath).lastPathComponent
            
        for ext in extensions {
            let directURL = base.appendingPathComponent("materials/\(rawPath).\(ext)")
            if FileManager.default.fileExists(atPath: directURL.path) { return directURL }
            let flatURL = base.appendingPathComponent("materials/\(fileName).\(ext)")
            if FileManager.default.fileExists(atPath: flatURL.path) { return flatURL }
        }
        return base.appendingPathComponent("materials/\(fileName).png")
    }
    
    func setPostProcessing(brightness: Float, contrast: Float, saturation: Float) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
    }
    
    func updateTransform(scale: Float, offset: SIMD2<Float>, rotation: Float) {
        self.userScale = scale
        self.userOffset = offset
        self.userRotation = rotation
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    // MARK: - Main Render Loop
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let descriptor = view.currentRenderPassDescriptor else { return }
        
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        descriptor.depthAttachment.clearDepth = 1.0
        descriptor.stencilAttachment.clearStencil = 0
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        
        encoder.setCullMode(.none)
        
        let proj = Matrix4x4.orthographic(left: 0, right: Float(projectionSize.width), bottom: 0, top: Float(projectionSize.height), near: -5000, far: 5000)
        
        let centerX = Float(projectionSize.width) / 2.0
        let centerY = Float(projectionSize.height) / 2.0
        var viewMat = Matrix4x4.identity
        
        if userScale != 1.0 || userRotation != 0 || userOffset != .zero {
            viewMat = Matrix4x4.translation(x: centerX + userOffset.x, y: centerY + userOffset.y, z: 0) *
                      Matrix4x4.rotation(angle: userRotation * .pi / 180.0, axis: SIMD3<Float>(0,0,1)) *
                      Matrix4x4.scale(x: userScale, y: userScale, z: 1.0) *
                      Matrix4x4.translation(x: -centerX, y: -centerY, z: 0)
        }
        
        let time = Float(Date().timeIntervalSince(startTime)) * timeScale
        
        var globals = GlobalUniforms(
            projectionMatrix: proj,
            viewMatrix: viewMat,
            time: time,
            brightness: brightness,
            contrast: contrast,
            saturation: saturation
        )
        
        encoder.setVertexBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
        encoder.setFragmentBytes(&globals, length: MemoryLayout<GlobalUniforms>.size, index: 1)
        
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentSamplerState(repeatSamplerState, index: 1)
        
        for obj in renderables {
            if let puppet = obj as? PuppetRenderable {
                puppet.updateAnimation(time: time)
            }
            obj.draw(encoder: encoder)
        }
        
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
