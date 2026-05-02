//
//  PuppetModels.swift
//  Renderer
//
//  Created by laobamac on 2026/2/27.
//

struct PuppetData: Codable {
    let info: PuppetInfo
    let skinning: [PuppetSkinning]
    let skeleton: [PuppetBone]
    let animations: [PuppetAnimation]
    let clipping_masks: [String]?
    let sub_meshes: [PuppetSubMesh]?
    let mask_bindings: [PuppetMaskBinding]?
}

struct PuppetSubMesh: Codable {
    let id: Int
    let start: Int
    let count: Int
}

struct PuppetMaskBinding: Codable {
    let target_group: Int
    let mask: Int?
}

struct PuppetInfo: Codable {
    let version: Int?
    let material_file: String?
}

struct PuppetSkinning: Codable {
    let vertex_id: Int
    let bone_indices: [UInt32]
    let weights: [Float]
}

struct PuppetBone: Codable {
    let id: Int
    let name: String
    let parent: Int
    let matrix: [Float]
    let render_tag: String?
}

struct PuppetAnimation: Codable {
    let id: Int
    let name: String
    let mode: String
    let fps: Float
    let length: Int
    let track_count: Int
    let tracks: [PuppetTrack]
}

struct PuppetTrack: Codable {
    let track_id: Int
    let frames: [PuppetKeyframe]
}

struct PuppetKeyframe: Codable {
    let time: Float?
    let p: [Float]
    let r: [Float]
    let s: [Float]
}
