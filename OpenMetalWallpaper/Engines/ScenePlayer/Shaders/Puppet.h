//
//  Puppet.h
//  Renderer
//
//  Created by laobamac on 2026/1/29.
//

#ifndef Puppet_H
#define Puppet_H

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float2 localCoord;
};

struct GlobalUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float time;
    float3 padding;
};

struct ObjectUniforms {
    float4x4 modelMatrix;
    float alpha;
    float4 color;
    float4 animInfo;
};

#endif // !Puppet_H
