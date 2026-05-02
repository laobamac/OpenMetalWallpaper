//
//  SceneLoader.swift
//  Renderer
//
//  Created by laobamac on 2026/3/13.
//

import Foundation
import MetalKit

struct SceneContext {
    var baseFolder: URL?
    var renderables: [RenderableObject] = []
    var projectionSize: CGSize = CGSize(width: 1920, height: 1080)
    var currentFOV: Float = 50.0
    var bloomThreshold: Float = 1.0
    var bloomStrength: Float = 2.0
    var bloomIterations: Int = 8
    var isHDREnabled: Bool = false
    var scaleMode: WallpaperScaleMode = .fill
    var brightness: Float = 0.0
    var contrast: Float = 1.0
    var saturation: Float = 1.0
}

class SceneLoader {
    let device: MTLDevice
    let pipelineManager: PipelineManager
    let textureManager: TextureManager
    let weAssetsURL: URL? = Bundle.main.resourceURL?.appendingPathComponent(
        "WEAssets"
    )

    init(device: MTLDevice, pipelineManager: PipelineManager, textureManager: TextureManager) {
        self.device = device
        self.pipelineManager = pipelineManager
        self.textureManager = textureManager
        Logger.debug("SceneLoader 初始化完成")
    }

    private func unpackIfNeeded(folder: URL) async {
        let fileManager = FileManager.default
        let materialsURL = folder.appendingPathComponent("materials")
        let pkgURL = folder.appendingPathComponent("scene.pkg")

        if !fileManager.fileExists(atPath: materialsURL.path)
            && fileManager.fileExists(atPath: pkgURL.path)
        {
            if let pkgParserURL = Bundle.main.resourceURL?
                .appendingPathComponent("Utils/pkg_parser")
            {
                await Task.detached(priority: .userInitiated) {
                    let process = Process()
                    process.executableURL = pkgParserURL
                    process.arguments = ["-d", pkgURL.path, "-o", folder.path]
                    try? process.run()
                    process.waitUntilExit()
                }.value
            }

            let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey]
            )

            guard let allFiles = enumerator?.allObjects as? [URL] else {
                return
            }

            if let mdlParserURL = Bundle.main.resourceURL?
                .appendingPathComponent("Utils/mdl_parser")
            {
                let maxConcurrentTasks = max(
                    2,
                    ProcessInfo.processInfo.activeProcessorCount
                )

                await withTaskGroup(of: Void.self) { group in
                    var activeTasks = 0
                    for fileURL in allFiles where fileURL.pathExtension == "mdl"
                    {
                        if activeTasks >= maxConcurrentTasks {
                            await group.next()
                            activeTasks -= 1
                        }
                        activeTasks += 1
                        group.addTask {
                            let process = Process()
                            process.executableURL = mdlParserURL
                            process.arguments = ["-d", fileURL.path]
                            try? process.run()
                            process.waitUntilExit()
                        }
                    }
                }
            }
        }
    }

    func loadScene(folder: URL) async -> SceneContext {
        await unpackIfNeeded(folder: folder)
        Logger.log("开始加载场景文件夹: \(folder.path)")
        var context = SceneContext()
        context.baseFolder = folder

        let secured = folder.startAccessingSecurityScopedResource()
        defer {
            if secured {
                folder.stopAccessingSecurityScopedResource()
                Logger.debug("释放安全作用域资源访问权限: \(folder.path)")
            }
        }

        Logger.debug("开始设置 TextureManager")
        await self.textureManager.setup(device: device)
        await self.textureManager.clear()
        Logger.debug("TextureManager 设置并清理完成")

        let projectURL = folder.appendingPathComponent("project.json")
        do {
            Logger.log("正在读取 project.json: \(projectURL.path)")
            let projData = try Data(contentsOf: projectURL)
            guard
                let projJson = try JSONSerialization.jsonObject(
                    with: projData,
                    options: []
                ) as? [String: Any],
                let sceneFile = projJson["file"] as? String
            else {
                Logger.error("解析 project.json 失败或找不到 file 字段")
                return context
            }

            Logger.log("发现场景文件: \(sceneFile)")
            let sceneURL = folder.appendingPathComponent(sceneFile)
            Logger.log("正在读取 scene.json: \(sceneURL.path)")
            let sceneData = try Data(contentsOf: sceneURL)
            let sceneRoot = try JSONDecoder().decode(
                SceneRoot.self,
                from: sceneData
            )
            Logger.log("scene.json 解码成功，共找到 \(sceneRoot.objects.count) 个对象定义")

            var rawObjects: [Int: [String: Any]] = [:]
            if let sceneDict = try JSONSerialization.jsonObject(with: sceneData)
                as? [String: Any],
                let objs = sceneDict["objects"] as? [[String: Any]]
            {
                for o in objs {
                    if let id = o["id"] as? Int {
                        rawObjects[id] = o
                    }
                }
                Logger.debug("成功提取 \(rawObjects.count) 个对象的原始 JSON 字典")
            }

            var isBloomEnabled = false
            if let sceneDict = try? JSONSerialization.jsonObject(
                with: sceneData
            ) as? [String: Any],
                let genDict = sceneDict["general"] as? [String: Any]
            {
                if let bloom = genDict["bloom"] as? Bool {
                    isBloomEnabled = bloom
                    Logger.debug("General 设置: bloom = \(bloom)")
                }
                if let hdr = genDict["hdr"] as? Bool {
                    context.isHDREnabled = hdr
                    Logger.debug("General 设置: hdr = \(hdr)")
                }
            }

            if let gen = sceneRoot.general {
                context.bloomThreshold = gen.bloomhdrthreshold ?? 1.0
                context.bloomStrength =
                    isBloomEnabled ? (gen.bloomhdrstrength ?? 2.0) : 0.0
                context.bloomIterations =
                    isBloomEnabled ? (gen.bloomhdriterations ?? 8) : 0
                Logger.debug(
                    "泛光设置: 阈值=\(context.bloomThreshold), 强度=\(context.bloomStrength), 迭代=\(context.bloomIterations)"
                )
            }

            if let proj = sceneRoot.general?.orthogonalprojection {
                context.projectionSize = CGSize(
                    width: Double(proj.width),
                    height: Double(proj.height)
                )
                Logger.debug("正交投影尺寸: \(context.projectionSize)")
            }
            if let fov = sceneRoot.general?.fov {
                context.currentFOV = fov
                Logger.debug("基础 FOV: \(fov)")
            }
            if let overrideFov = sceneRoot.general?.perspectiveoverridefov,
                overrideFov > 0
            {
                context.currentFOV = overrideFov
                Logger.debug("覆盖 FOV: \(overrideFov)")
            }

            var tempRenderables: [Int: RenderableObject] = [:]
            var orderedList: [RenderableObject] = []

            Logger.log("开始遍历并创建场景对象...")
            let results = await withTaskGroup(
                of: (Int, RenderableObject?, Int?, Int?).self
            ) { group -> [(Int, RenderableObject)] in
                for (index, obj) in sceneRoot.objects.enumerated() {
                    if !obj.isVisible {
                        Logger.debug(
                            "对象 [\(obj.name ?? "Unknown")] (ID:\(obj.id ?? -1)) 设为不可见，跳过"
                        )
                        continue
                    }
                    Logger.debug(
                        "正在处理对象 [\(obj.name ?? "Unknown")] (ID:\(obj.id ?? -1))"
                    )
                    let rawObj = rawObjects[obj.id ?? -1]
                    group.addTask {
                        let renderable = await self.createRenderable(
                            from: obj,
                            raw: rawObj,
                            baseFolder: folder
                        )
                        return (index, renderable, obj.id, obj.parent)
                    }
                }

                var gathered: [(Int, RenderableObject)] = []
                for await (index, renderable, objId, parentId) in group {
                    if let r = renderable {
                        if let id = objId {
                            r.id = id
                            Logger.debug("对象 ID:\(id) 成功加入渲染列表")
                        }
                        r.parentId = parentId
                        gathered.append((index, r))
                    } else {
                        Logger.error("对象 (ID:\(objId ?? -1)) 创建 Renderable 失败")
                    }
                }
                return gathered.sorted { $0.0 < $1.0 }
            }

            Logger.log("开始建立父子层级关系...")
            for (_, renderable) in results {
                tempRenderables[renderable.id] = renderable
                orderedList.append(renderable)
            }

            for renderable in orderedList {
                if let pid = renderable.parentId,
                    let parentObj = tempRenderables[pid]
                {
                    renderable.parent = parentObj
                    Logger.debug("将对象 ID:\(renderable.id) 的父节点设为 ID:\(pid)")
                }
            }

            context.renderables = orderedList
            Logger.log("场景加载完成，总共包含 \(orderedList.count) 个活跃渲染对象")
        } catch {
            Logger.error("加载场景时发生错误: \(error.localizedDescription)")
        }
        return context
    }

    private func createRenderable(
        from obj: SceneObject,
        raw: [String: Any]?,
        baseFolder: URL
    ) async -> RenderableObject? {
        guard let imagePath = obj.image else {
            Logger.debug("对象 [\(obj.name ?? "Unknown")] 没有 imagePath，返回 nil")
            return nil
        }
        Logger.debug("对象 [\(obj.name ?? "Unknown")] imagePath: \(imagePath)")
        let modelURL = resolveAssetURL(base: baseFolder, rawPath: imagePath)
        let fileName = modelURL.deletingPathExtension().lastPathComponent
        let puppetDataURL = modelURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileName)_puppet_data.json")
        let puppetObjURL = modelURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileName)_puppet.obj")

        if FileManager.default.fileExists(atPath: puppetDataURL.path) {
            Logger.log(
                "检测到 Puppet 数据文件: \(puppetDataURL.lastPathComponent)，进入 Puppet 创建流程"
            )
            return await createPuppetRenderable(
                from: obj,
                dataURL: puppetDataURL,
                objURL: puppetObjURL,
                baseFolder: baseFolder
            )
        }

        Logger.debug("未检测到 Puppet 数据，按普通模型/图片处理: \(modelURL.path)")
        do {
            let modelData = try Data(contentsOf: modelURL)
            let modelDef = try JSONDecoder().decode(
                ModelJSON.self,
                from: modelData
            )

            guard let matPath = modelDef.material else {
                Logger.error("普通模型缺少 material 字段")
                return nil
            }
            Logger.debug("读取材质文件: \(matPath)")
            let matURL = resolveAssetURL(base: baseFolder, rawPath: matPath)
            let matData = try Data(contentsOf: matURL)
            let matDef = try JSONDecoder().decode(
                MaterialJSON.self,
                from: matData
            )

            guard let firstPass = matDef.passes.first else {
                Logger.error("材质文件没有 passes")
                return nil
            }

            var texture: MTLTexture!
            var frameInfo: [TexFrameInfo]? = nil
            var isVideo: Bool = false

            if let texName = firstPass.textures.first {
                Logger.debug("正在加载纹理: \(texName)")
                let texURL = resolveTextureURL(
                    base: baseFolder,
                    rawPath: texName
                )
                let result = try await self.textureManager.loadTexture(
                    url: texURL,
                    options: [
                        .origin: MTKTextureLoader.Origin.topLeft, .SRGB: true,
                    ]
                )
                texture = result.0
                isVideo = result.1
                frameInfo = await self.textureManager.frameInfo(for: texURL)
                Logger.debug("纹理加载成功: \(texName)")
            } else {
                Logger.debug("材质中没有纹理，创建纯色占位纹理")
                let (_, _, size, _) = RenderableObject.parseTransforms(obj)
                let w = max(1, Int(size.x))
                let h = max(1, Int(size.y))
                let desc = MTLTextureDescriptor()
                desc.textureType = .type2DArray
                desc.pixelFormat = .rgba16Float
                desc.width = w
                desc.height = h
                desc.arrayLength = 1
                desc.usage = [.shaderRead, .renderTarget, .pixelFormatView]
                texture = device.makeTexture(descriptor: desc)!
                let bytes = [UInt8](repeating: 0, count: w * h * 8)
                texture.replace(
                    region: MTLRegionMake2D(0, 0, w, h),
                    mipmapLevel: 0,
                    slice: 0,
                    withBytes: bytes,
                    bytesPerRow: w * 8,
                    bytesPerImage: w * h * 8
                )
            }

            let (pos, rotation, size, scale) = RenderableObject.parseTransforms(
                obj
            )
            Logger.debug(
                "对象变换 - 位置:\(pos), 旋转:\(rotation), 尺寸:\(size), 缩放:\(scale)"
            )
            var depthState = pipelineManager.depthStencilState
            if let dw = firstPass.depthwrite, dw == "disabled" {
                Logger.debug("对象关闭深度写入")
                depthState = pipelineManager.depthWriteDisabledState
            }

            let blendMode = obj.colorBlendMode ?? 0
            Logger.debug("请求混合模式: \(blendMode)")
            guard
                let pipeline = pipelineManager.getPipeline(
                    isPuppet: false,
                    blendMode: blendMode
                )
            else {
                Logger.error(
                    "获取 pipeline 失败 (isPuppet: false, blendMode: \(blendMode))"
                )
                return nil
            }

            Logger.log("成功创建普通 RenderableObject: \(obj.name ?? "")")
            return RenderableObject(
                position: pos,
                rotation: rotation,
                size: size,
                scale: scale,
                texture: texture,
                frameInfo: frameInfo,
                isVideo: isVideo,
                pipeline: pipeline,
                depthState: depthState
            )
        } catch {
            Logger.error("创建普通对象失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func createPuppetRenderable(
        from obj: SceneObject,
        dataURL: URL,
        objURL: URL,
        baseFolder: URL
    ) async -> RenderableObject? {
        do {
            Logger.debug("读取 Puppet JSON: \(dataURL.path)")
            let jsonData = try Data(contentsOf: dataURL)
            let puppetData = try JSONDecoder().decode(
                PuppetData.self,
                from: jsonData
            )
            Logger.debug("读取 Puppet OBJ: \(objURL.path)")
            let objContent = try String(contentsOf: objURL, encoding: .utf8)

            guard let matFile = puppetData.info.material_file else {
                Logger.error("Puppet JSON 缺少 material_file")
                return nil
            }
            Logger.debug("读取 Puppet 材质: \(matFile)")
            let matURL = resolveAssetURL(base: baseFolder, rawPath: matFile)
            let matData = try Data(contentsOf: matURL)
            let matDef = try JSONDecoder().decode(
                MaterialJSON.self,
                from: matData
            )

            guard let firstPass = matDef.passes.first,
                let texName = firstPass.textures.first
            else {
                Logger.error("Puppet 材质缺少纹理配置")
                return nil
            }

            let texURL = resolveTextureURL(base: baseFolder, rawPath: texName)
            Logger.debug("开始加载 Puppet 基础纹理: \(texURL.lastPathComponent)")
            let result = try await self.textureManager.loadTexture(
                url: texURL,
                options: [
                    .origin: MTKTextureLoader.Origin.topLeft, .SRGB: true,
                ]
            )
            let texture = result.0
            let isVideo = result.1
            let frameInfo = await self.textureManager.frameInfo(for: texURL)

            Logger.debug("开始解析 Puppet OBJ...")
            let (vertices, indices, bboxWidth) = PuppetRenderable.parseOBJ(
                objContent: objContent,
                skinning: puppetData.skeleton.isEmpty ? [] : puppetData.skinning
            )
            Logger.debug(
                "Puppet OBJ 解析完成, 顶点:\(vertices.count), 索引:\(indices.count), 边界宽:\(bboxWidth)"
            )

            let (pos, rotation, size, scale) = RenderableObject.parseTransforms(
                obj
            )
            var depthState = pipelineManager.depthStencilState
            if let dw = firstPass.depthwrite, dw == "disabled" {
                depthState = pipelineManager.depthWriteDisabledState
            }

            var maskTextures: [MTLTexture] = []
            if let masks = puppetData.clipping_masks {
                Logger.debug("Puppet 包含 \(masks.count) 个裁剪遮罩")
                for (index, maskPath) in masks.enumerated() {
                    let mURL = resolveTextureURL(
                        base: baseFolder,
                        rawPath: maskPath
                    )
                    Logger.debug(
                        "正在加载第 \(index) 个遮罩: \(mURL.lastPathComponent)"
                    )
                    if let result = try? await self.textureManager
                        .loadTexture(
                            url: mURL,
                            options: [
                                .origin: MTKTextureLoader.Origin.topLeft,
                                .SRGB: false,
                            ]
                        )
                    {
                        maskTextures.append(result.0)
                        Logger.debug("遮罩加载成功")
                    } else {
                        Logger.error("遮罩加载失败: \(maskPath)")
                    }
                }
            } else {
                Logger.debug("Puppet 不包含裁剪遮罩")
            }

            let blendMode = obj.colorBlendMode ?? 0
            guard
                let pipeline = pipelineManager.getPipeline(
                    isPuppet: true,
                    blendMode: blendMode
                ),
                let maskPipe = pipelineManager.puppetMaskPipelineState
            else {
                Logger.error("Puppet pipeline 获取失败")
                return nil
            }

            Logger.log("成功创建 PuppetRenderable: \(obj.name ?? "")")
            return PuppetRenderable(
                device: device,
                vertices: vertices,
                indices: indices,
                subMeshes: puppetData.sub_meshes,
                maskBindings: puppetData.mask_bindings,
                skeleton: puppetData.skeleton,
                animations: puppetData.animations,
                animationLayers: obj.animationlayers ?? [],
                position: pos,
                rotation: rotation,
                size: size,
                scale: scale,
                texture: texture,
                frameInfo: frameInfo,
                isVideo: isVideo,
                maskTextures: maskTextures,
                maskWriteState: pipelineManager.maskWriteState,
                maskTestState: pipelineManager.maskTestState,
                puppetMaskPipeline: maskPipe,
                pipeline: pipeline,
                depthState: depthState,
                usePixelCoords: bboxWidth > 2.0
            )
        } catch {
            Logger.error("创建 Puppet 对象失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func resolveAssetURL(base: URL, rawPath: String) -> URL {
        let cleanPath = rawPath.replacingOccurrences(of: "\\", with: "/")
        var searchPaths = [cleanPath]

        if !cleanPath.hasPrefix("materials/") && !cleanPath.hasPrefix("models/")
            && !cleanPath.hasPrefix("particles/")
        {
            searchPaths.append("materials/\(cleanPath)")
        }

        for path in searchPaths {
            let local = base.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: local.path) {
                return local
            }
        }

        if let weAssets = weAssetsURL {
            for path in searchPaths {
                let fallback = weAssets.appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: fallback.path) {
                    Logger.debug("找到 WEAssets 通用资源: \(path)")
                    return fallback
                }
            }
        }

        return base.appendingPathComponent(cleanPath)
    }

    private func resolveTextureURL(base: URL, rawPath: String) -> URL {
        let cleanPath = rawPath.replacingOccurrences(of: "\\", with: "/")
        let fileName = URL(fileURLWithPath: cleanPath).deletingPathExtension()
            .lastPathComponent

        let p1 = "materials/\(cleanPath).tex"
        let p2 = "materials/\(fileName).tex"
        let p3 = URL(fileURLWithPath: cleanPath).deletingPathExtension()
            .appendingPathExtension("tex").path

        let searchPaths = [p1, p2, p3]

        for path in searchPaths {
            let local = base.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: local.path) {
                Logger.debug("找到纹理 (Local): \(local.path)")
                return local
            }
        }

        if let weAssets = weAssetsURL {
            for path in searchPaths {
                let fallback = weAssets.appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: fallback.path) {
                    Logger.debug("找到 WEAssets 通用纹理: \(fallback.path)")
                    return fallback
                }
            }
        }

        let finalFallback = base.appendingPathComponent(
            "materials/\(fileName).tex"
        )
        Logger.debug("未找到精确匹配纹理，使用 Fallback: \(finalFallback.path)")
        return finalFallback
    }
}
