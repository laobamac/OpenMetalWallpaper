//
//  PipelineManager.swift
//  Renderer
//
//  Created by laobamac on 2026/3/13.
//

import MetalKit

class PipelineManager {
    let device: MTLDevice
    var library: MTLLibrary?
    let hdrFormat: MTLPixelFormat = .rgba16Float
    let depthFormat: MTLPixelFormat = .depth32Float_stencil8

    var pipelineStates: [Int: MTLRenderPipelineState] = [:]
    var puppetPipelineStates: [Int: MTLRenderPipelineState] = [:]
    var puppetMaskPipelineState: MTLRenderPipelineState?
    var extractPipeline: MTLRenderPipelineState?
    var blurPipeline: MTLRenderPipelineState?
    var upsamplePipeline: MTLRenderPipelineState?
    var finalPipeline: MTLRenderPipelineState?
    var samplerState: MTLSamplerState?
    var depthStencilState: MTLDepthStencilState?
    var depthWriteDisabledState: MTLDepthStencilState?
    var maskWriteState: MTLDepthStencilState?
    var maskTestState: MTLDepthStencilState?

    init(device: MTLDevice) {
        self.device = device
        self.library = device.makeDefaultLibrary()
        if self.library == nil {
            Logger.error("PipelineManager 构造失败: 无法创建 DefaultLibrary")
        } else {
            Logger.debug("PipelineManager 构造成功, DefaultLibrary 已加载")
        }
    }

    var pipelineState: MTLRenderPipelineState? {
        return getPipeline(isPuppet: false, blendMode: 0)
    }

    var puppetPipelineState: MTLRenderPipelineState? {
        return getPipeline(isPuppet: true, blendMode: 0)
    }

    func configureBlend(
        descriptor: MTLRenderPipelineColorAttachmentDescriptor,
        blendMode: Int
    ) {
        Logger.debug("配置 BlendMode: \(blendMode)")
        descriptor.isBlendingEnabled = true
        switch blendMode {
        case 1, 7:
            descriptor.rgbBlendOperation = .add
            descriptor.alphaBlendOperation = .add
            descriptor.sourceRGBBlendFactor = .sourceAlpha
            descriptor.destinationRGBBlendFactor = .one
            descriptor.sourceAlphaBlendFactor = .sourceAlpha
            descriptor.destinationAlphaBlendFactor = .one
        case 12, 31:
            descriptor.rgbBlendOperation = .add
            descriptor.alphaBlendOperation = .add
            descriptor.sourceRGBBlendFactor = .one
            descriptor.destinationRGBBlendFactor = .oneMinusSourceColor
            descriptor.sourceAlphaBlendFactor = .one
            descriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case 2, 3:
            descriptor.rgbBlendOperation = .add
            descriptor.alphaBlendOperation = .add
            descriptor.sourceRGBBlendFactor = .destinationColor
            descriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.sourceAlphaBlendFactor = .destinationAlpha
            descriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        default:
            descriptor.rgbBlendOperation = .add
            descriptor.alphaBlendOperation = .add
            descriptor.sourceRGBBlendFactor = .sourceAlpha
            descriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.sourceAlphaBlendFactor = .sourceAlpha
            descriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
    }

    func getPipeline(isPuppet: Bool, blendMode: Int) -> MTLRenderPipelineState?
    {
        if isPuppet {
            if let state = puppetPipelineStates[blendMode] { return state }
        } else {
            if let state = pipelineStates[blendMode] { return state }
        }

        Logger.debug(
            "缓存未命中，开始创建新的 Pipeline (isPuppet: \(isPuppet), blendMode: \(blendMode))"
        )

        guard let lib = library else {
            Logger.error("创建 Pipeline 失败: Library 为空")
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label =
            isPuppet ? "Puppet_\(blendMode)" : "Standard_\(blendMode)"
        descriptor.vertexFunction = lib.makeFunction(
            name: isPuppet ? "vertex_puppet" : "vertex_main"
        )
        descriptor.fragmentFunction = lib.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = hdrFormat
        if let colorAttachment = descriptor.colorAttachments[0] {
            configureBlend(descriptor: colorAttachment, blendMode: blendMode)
        }
        descriptor.depthAttachmentPixelFormat = depthFormat
        descriptor.stencilAttachmentPixelFormat = depthFormat

        let vertexDescriptor = MTLVertexDescriptor()
        if isPuppet {
            var offset = 0
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = offset
            vertexDescriptor.attributes[0].bufferIndex = 0
            offset += 16
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.attributes[1].offset = offset
            vertexDescriptor.attributes[1].bufferIndex = 0
            offset += 8
            vertexDescriptor.attributes[2].format = .ushort4
            vertexDescriptor.attributes[2].offset = offset
            vertexDescriptor.attributes[2].bufferIndex = 0
            offset += 8
            vertexDescriptor.attributes[3].format = .float4
            vertexDescriptor.attributes[3].offset = offset
            vertexDescriptor.attributes[3].bufferIndex = 0
            offset += 16
            vertexDescriptor.layouts[0].stride = 48
        } else {
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.attributes[1].offset = 12
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = 20
        }
        descriptor.vertexDescriptor = vertexDescriptor

        do {
            let state = try device.makeRenderPipelineState(
                descriptor: descriptor
            )
            if isPuppet {
                puppetPipelineStates[blendMode] = state
            } else {
                pipelineStates[blendMode] = state
            }
            Logger.log("成功创建并缓存 Pipeline: \(descriptor.label ?? "未知")")
            return state
        } catch {
            Logger.error("创建 Pipeline 失败: \(error.localizedDescription)")
            return nil
        }
    }

    func setupPipelines() async throws {
        Logger.log("开始全局初始化 Pipelines 和相关状态")
        guard let lib = library else {
            Logger.error("全局初始化失败: Library 为空")
            throw NSError(
                domain: "Renderer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Library error"]
            )
        }

        _ = getPipeline(isPuppet: false, blendMode: 0)
        _ = getPipeline(isPuppet: true, blendMode: 0)

        Logger.debug("配置 PuppetMask Pipeline")
        let maskDesc = MTLRenderPipelineDescriptor()
        maskDesc.label = "PuppetMask"
        maskDesc.vertexFunction = lib.makeFunction(name: "vertex_puppet")
        maskDesc.fragmentFunction = lib.makeFunction(
            name: "fragment_puppet_mask"
        )
        maskDesc.colorAttachments[0].pixelFormat = hdrFormat
        maskDesc.colorAttachments[0].writeMask = []
        maskDesc.depthAttachmentPixelFormat = depthFormat
        maskDesc.stencilAttachmentPixelFormat = depthFormat
        let pvDesc = MTLVertexDescriptor()
        var offset = 0
        pvDesc.attributes[0].format = .float3
        pvDesc.attributes[0].offset = offset
        pvDesc.attributes[0].bufferIndex = 0
        offset += 16
        pvDesc.attributes[1].format = .float2
        pvDesc.attributes[1].offset = offset
        pvDesc.attributes[1].bufferIndex = 0
        offset += 8
        pvDesc.attributes[2].format = .ushort4
        pvDesc.attributes[2].offset = offset
        pvDesc.attributes[2].bufferIndex = 0
        offset += 8
        pvDesc.attributes[3].format = .float4
        pvDesc.attributes[3].offset = offset
        pvDesc.attributes[3].bufferIndex = 0
        offset += 16
        pvDesc.layouts[0].stride = 48
        maskDesc.vertexDescriptor = pvDesc
        puppetMaskPipelineState = try await device.makeRenderPipelineState(
            descriptor: maskDesc,
            options: []
        ).0
        Logger.debug("PuppetMask Pipeline 创建成功")

        Logger.debug("配置后期处理 Pipeline")
        let postDesc = MTLRenderPipelineDescriptor()
        postDesc.vertexFunction = lib.makeFunction(name: "vertex_post")
        postDesc.colorAttachments[0].pixelFormat = hdrFormat
        postDesc.depthAttachmentPixelFormat = .invalid
        postDesc.stencilAttachmentPixelFormat = .invalid
        postDesc.fragmentFunction = lib.makeFunction(name: "fragment_extract")
        extractPipeline = try await device.makeRenderPipelineState(
            descriptor: postDesc,
            options: []
        ).0
        Logger.debug("提取 Pipeline 创建成功")

        postDesc.fragmentFunction = lib.makeFunction(name: "fragment_blur")
        blurPipeline = try await device.makeRenderPipelineState(
            descriptor: postDesc,
            options: []
        ).0
        Logger.debug("模糊 Pipeline 创建成功")

        postDesc.fragmentFunction = lib.makeFunction(name: "fragment_upsample")
        upsamplePipeline = try await device.makeRenderPipelineState(
            descriptor: postDesc,
            options: []
        ).0
        Logger.debug("上采样 Pipeline 创建成功")

        postDesc.fragmentFunction = lib.makeFunction(name: "fragment_final")
        postDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        postDesc.depthAttachmentPixelFormat = depthFormat
        postDesc.stencilAttachmentPixelFormat = depthFormat
        finalPipeline = try await device.makeRenderPipelineState(
            descriptor: postDesc,
            options: []
        ).0
        Logger.debug("最终合成 Pipeline 创建成功")

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.normalizedCoordinates = true
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
        Logger.debug("默认 SamplerState 创建成功")
        Logger.log("全局初始化 Pipelines 完成")
    }

    func setupDepthStencilStates() {
        Logger.debug("开始设置 DepthStencil 状态")
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.isDepthWriteEnabled = true
        depthDesc.depthCompareFunction = .lessEqual
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)

        let depthDisabledDesc = MTLDepthStencilDescriptor()
        depthDisabledDesc.isDepthWriteEnabled = false
        depthDisabledDesc.depthCompareFunction = .lessEqual
        depthWriteDisabledState = device.makeDepthStencilState(
            descriptor: depthDisabledDesc
        )

        let maskWriteDesc = MTLDepthStencilDescriptor()
        maskWriteDesc.isDepthWriteEnabled = false
        maskWriteDesc.depthCompareFunction = .always
        let sw = MTLStencilDescriptor()
        sw.stencilCompareFunction = .always
        sw.stencilFailureOperation = .keep
        sw.depthFailureOperation = .keep
        sw.depthStencilPassOperation = .replace
        sw.readMask = 0xFF
        sw.writeMask = 0xFF
        maskWriteDesc.frontFaceStencil = sw
        maskWriteDesc.backFaceStencil = sw
        maskWriteState = device.makeDepthStencilState(descriptor: maskWriteDesc)

        let maskTestDesc = MTLDepthStencilDescriptor()
        maskTestDesc.isDepthWriteEnabled = false
        maskTestDesc.depthCompareFunction = .always
        let st = MTLStencilDescriptor()
        st.stencilCompareFunction = .equal
        st.stencilFailureOperation = .keep
        st.depthFailureOperation = .keep
        st.depthStencilPassOperation = .keep
        st.readMask = 0xFF
        st.writeMask = 0x00
        maskTestDesc.frontFaceStencil = st
        maskTestDesc.backFaceStencil = st
        maskTestState = device.makeDepthStencilState(descriptor: maskTestDesc)
        Logger.debug("DepthStencil 状态全部设置完成")
    }
}
