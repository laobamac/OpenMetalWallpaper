//
//  Puppet.metal
//  Renderer
//
//  Created by laobamac on 2026/2/7.
//

#include <metal_stdlib>
#include "Puppet.h"
using namespace metal;

struct PuppetVertexIn {
    float3 position  [[attribute(0)]];
    float2 texCoord  [[attribute(1)]];
    ushort4 joints   [[attribute(2)]];
    float4 weights   [[attribute(3)]];
};

struct PuppetUniforms {
    float4x4 bones[100];
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant GlobalUniforms &globals [[buffer(1)]],
                             constant ObjectUniforms &object [[buffer(2)]]) {
    VertexOut out;
    float4 pos = float4(in.position, 1.0);
    out.position = globals.projectionMatrix * globals.viewMatrix * object.modelMatrix * pos;
    out.texCoord = in.texCoord * object.animInfo.zw + object.animInfo.xy;
    out.localCoord = in.texCoord - 0.5;
    return out;
}

vertex VertexOut vertex_puppet(PuppetVertexIn in [[stage_in]],
                               constant GlobalUniforms &globals [[buffer(1)]],
                               constant ObjectUniforms &object [[buffer(2)]],
                               constant PuppetUniforms &puppet [[buffer(3)]])
{
    VertexOut out;
    
    float4x4 skinMatrix = float4x4(0.0);
    bool hasBones = false;
    float totalWeight = 0.0;
    
    for (int i = 0; i < 4; i++) {
        totalWeight += in.weights[i];
    }
    
    for (int i = 0; i < 4; i++) {
        int boneIndex = int(in.joints[i]);
        float weight = in.weights[i];
        if (weight > 0.0) {
            float normalizedWeight = totalWeight > 0.0 ? (weight / totalWeight) : 0.0;
            skinMatrix += puppet.bones[boneIndex] * normalizedWeight;
            hasBones = true;
        }
    }
    
    if (!hasBones || totalWeight == 0.0) {
        skinMatrix = float4x4(1.0);
    }
    
    float4 pos = float4(in.position, 1.0);
    float4 localPos = skinMatrix * pos;
    float4 worldPos = object.modelMatrix * localPos;
    
    out.position = globals.projectionMatrix * globals.viewMatrix * worldPos;
    out.texCoord = in.texCoord * object.animInfo.zw + object.animInfo.xy;
    out.localCoord = in.texCoord - 0.5;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant GlobalUniforms &globals [[buffer(1)]],
                              constant ObjectUniforms &object [[buffer(2)]],
                              texture2d_array<float> baseTexture [[texture(0)]],
                              sampler textureSampler [[sampler(0)]])
{
    float4 color = baseTexture.sample(textureSampler, in.texCoord, 0);
    color *= object.color;
    color.a *= object.alpha;
    return color;
}

fragment float4 fragment_puppet_mask(VertexOut in [[stage_in]],
                                     texture2d_array<float> maskTexture [[texture(0)]],
                                     sampler textureSampler [[sampler(0)]])
{
    float4 maskColor = maskTexture.sample(textureSampler, in.texCoord, 0);
    float maskAlpha = maskColor.r * maskColor.a;
    if (maskAlpha < 0.1) {
        discard_fragment();
    }
    return float4(1.0);
}
