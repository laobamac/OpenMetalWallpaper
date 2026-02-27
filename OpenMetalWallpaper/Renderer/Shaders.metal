//
//  Shaders.metal
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/24.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct PuppetVertexIn {
    float3 position  [[attribute(0)]];
    float2 texCoord  [[attribute(1)]];
    ushort4 joints   [[attribute(2)]];
    float4 weights   [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float2 localCoord;
};

// [Modified] Added PostProcessing Uniforms
struct GlobalUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float time;
    float brightness;
    float contrast;
    float saturation;
};

struct ObjectUniforms {
    float4x4 modelMatrix;
    float alpha;
    float4 color;
    float4 padding;
};

struct PuppetUniforms {
    float4x4 bones[100];
};

struct EffectParams {
    int type;
    int maskIndex;
    float speed;
    float scale;
    float strength;
    float exponent;
    float2 direction;
    float2 bounds;
    float2 friction;
    float4 color;
};

enum EffectType {
    EffectTypeNone = 0,
    EffectTypeScroll = 1,
    EffectTypeWaterWave = 2,
    EffectTypeShake = 3,
    EffectTypeFoliageSway = 4,
    EffectTypeWaterRipple = 5,
    EffectTypePulse = 6,
    EffectTypeTint = 7
};

// --- Helper for Saturation ---
float3 applySaturation(float3 rgb, float adjustment) {
    const float3 W = float3(0.2125, 0.7154, 0.0721);
    float3 intensity = float3(dot(rgb, W));
    return mix(intensity, rgb, adjustment);
}

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant GlobalUniforms &globals [[buffer(1)]],
                             constant ObjectUniforms &object [[buffer(2)]]) {
    VertexOut out;
    float4 pos = float4(in.position, 1.0);
    out.position = globals.projectionMatrix * globals.viewMatrix * object.modelMatrix * pos;
    out.texCoord = in.texCoord;
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
    for (int i = 0; i < 4; i++) {
        int boneIndex = int(in.joints[i]);
        float weight = in.weights[i];
        if (weight > 0.0) {
            skinMatrix += puppet.bones[boneIndex] * weight;
            hasBones = true;
        }
    }
    if (!hasBones) skinMatrix = float4x4(1.0);
    
    float4 pos = float4(in.position, 1.0);
    float4 localPos = skinMatrix * pos;
    float4 worldPos = object.modelMatrix * localPos;
    
    out.position = globals.projectionMatrix * globals.viewMatrix * worldPos;
    out.texCoord = in.texCoord;
    out.localCoord = in.texCoord - 0.5;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant GlobalUniforms &globals [[buffer(1)]],
                              constant ObjectUniforms &object [[buffer(2)]],
                              constant EffectParams *effects [[buffer(3)]],
                              constant int &effectCount [[buffer(4)]],
                              texture2d<float> baseTexture [[texture(0)]],
                              array<texture2d<float>, 8> maskTextures [[texture(1)]],
                              sampler textureSampler [[sampler(0)]],
                              sampler repeatSampler [[sampler(1)]])
{
    float2 uv = in.texCoord;
    float2 originalUV = uv;

    // --- Effect Processing (Scroll, Wave, etc.) ---
    for (int i = 0; i < effectCount; i++) {
        EffectParams e = effects[i];
        if (e.type == EffectTypeScroll) {
            float2 scrollOffset = float2(e.direction.x, e.direction.y) * globals.time * 0.1;
            uv = uv - scrollOffset;
            uv = uv - floor(uv);
        } else if (e.type == EffectTypeWaterWave) {
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            float2 dir = e.direction;
            float distance = globals.time * e.speed + dot(uv, dir) * e.scale;
            float val = pow(abs(sin(distance)), e.exponent) * sign(sin(distance));
            uv += val * float2(dir.y, -dir.x) * e.strength * mask * 0.03;
        } else if (e.type == EffectTypeShake) {
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            float t = globals.time * e.speed;
            float2 offset = e.direction * sin(t) * e.strength * mask * 0.1;
            uv += offset;
        } else if (e.type == EffectTypeFoliageSway) {
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            float t = globals.time * e.speed;
            float spatial = (originalUV.x + originalUV.y) / max(e.scale, 0.001);
            float val = sin(t + spatial + e.exponent);
            uv += e.direction * val * e.strength * mask * 0.005;
        } else if (e.type == EffectTypeWaterRipple) {
            float mask = 1.0;
            if (e.maskIndex >= 0 && e.maskIndex < 8) mask = maskTextures[e.maskIndex].sample(textureSampler, originalUV).r;
            float3 normal = float3(0.5, 0.5, 1.0);
            int normalIdx = e.maskIndex + 1;
            if (normalIdx >= 0 && normalIdx < 8) {
                float activeSpeed = e.speed + e.friction.x;
                float2 scroll = e.direction * globals.time * activeSpeed;
                float2 normalUV = originalUV * e.scale + scroll;
                normal = maskTextures[normalIdx].sample(repeatSampler, normalUV).rgb;
            }
            float2 offset = (normal.xy * 2.0 - 1.0) * e.strength * mask * 0.1;
            uv += offset;
        }
    }
    
    float4 color = baseTexture.sample(textureSampler, uv);
    
    // --- Color Effects (Pulse, Tint) ---
    for (int i = 0; i < effectCount; i++) {
        EffectParams e = effects[i];
        if (e.type == EffectTypePulse) {
            float mask = 0.0;
            int maskIdx = e.maskIndex + 1;
            if (maskIdx >= 0 && maskIdx < 8) mask = maskTextures[maskIdx].sample(textureSampler, originalUV).r;
            float noiseVal = 0.5;
            if (e.maskIndex >= 0 && e.maskIndex < 8) {
                float2 noiseUV = originalUV + globals.time * e.speed;
                noiseVal = maskTextures[e.maskIndex].sample(repeatSampler, noiseUV).r;
            }
            float pulse = e.bounds.x + noiseVal * e.strength;
            color.rgb += e.color.rgb * pulse * mask * e.color.a;
        } else if (e.type == EffectTypeTint) {
            color.rgb = mix(color.rgb, e.color.rgb, e.strength);
        }
    }
    
    color *= object.color;
    color.a *= object.alpha;
    
    // --- [New] Global Post Processing ---
    // Brightness
    color.rgb += globals.brightness;
    // Contrast
    color.rgb = (color.rgb - 0.5) * globals.contrast + 0.5;
    // Saturation
    color.rgb = applySaturation(color.rgb, globals.saturation);
    
    return color;
}
