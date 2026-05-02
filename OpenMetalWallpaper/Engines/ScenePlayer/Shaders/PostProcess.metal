//
//  PostProcess.metal
//  Renderer
//
//  Created by laobamac on 2026/2/11.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_post(uint vertexID [[vertex_id]]) {
    float2 coords[4] = {
        float2(-1.0, -1.0),
        float2(1.0, -1.0),
        float2(-1.0, 1.0),
        float2(1.0, 1.0)
    };
    VertexOut out;
    out.position = float4(coords[vertexID], 0.0, 1.0);
    out.texCoord = coords[vertexID] * 0.5 + 0.5;
    out.texCoord.y = 1.0 - out.texCoord.y;
    return out;
}

fragment float4 fragment_extract(VertexOut in [[stage_in]],
                                 texture2d<float> sceneTexture [[texture(0)]],
                                 sampler s [[sampler(0)]],
                                 constant float &threshold [[buffer(0)]]) {
    float4 color = sceneTexture.sample(s, in.texCoord);
    float luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    return (luma > threshold) ? color : float4(0.0, 0.0, 0.0, 1.0);
}

fragment float4 fragment_blur(VertexOut in [[stage_in]],
                              texture2d<float> inputTexture [[texture(0)]],
                              sampler s [[sampler(0)]],
                              constant bool &horizontal [[buffer(0)]]) {
    float weight[5] = {0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216};
    float2 texelSize = 1.0 / float2(inputTexture.get_width(), inputTexture.get_height());
    float3 result = inputTexture.sample(s, in.texCoord).rgb * weight[0];
    if (horizontal) {
        for (int i = 1; i < 5; ++i) {
            result += inputTexture.sample(s, in.texCoord + float2(texelSize.x * i, 0.0)).rgb * weight[i];
            result += inputTexture.sample(s, in.texCoord - float2(texelSize.x * i, 0.0)).rgb * weight[i];
        }
    } else {
        for (int i = 1; i < 5; ++i) {
            result += inputTexture.sample(s, in.texCoord + float2(0.0, texelSize.y * i)).rgb * weight[i];
            result += inputTexture.sample(s, in.texCoord - float2(0.0, texelSize.y * i)).rgb * weight[i];
        }
    }
    return float4(result, 1.0);
}

fragment float4 fragment_upsample(VertexOut in [[stage_in]],
                                  texture2d<float> lowerResTexture [[texture(0)]],
                                  texture2d<float> higherResTexture [[texture(1)]],
                                  sampler s [[sampler(0)]]) {
    float3 lowerResColor = lowerResTexture.sample(s, in.texCoord).rgb;
    float3 higherResColor = higherResTexture.sample(s, in.texCoord).rgb;
    return float4(lowerResColor + higherResColor, 1.0);
}

float3 aces_tonemap(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

fragment float4 fragment_final(VertexOut in [[stage_in]],
                               texture2d<float> sceneTexture [[texture(0)]],
                               texture2d<float> bloomTexture [[texture(1)]],
                               sampler s [[sampler(0)]],
                               constant float &bloomStrength [[buffer(0)]],
                               constant bool &isHDREnabled [[buffer(1)]],
                               constant float3 &postParams [[buffer(2)]]) {
    float3 sceneColor = sceneTexture.sample(s, in.texCoord).rgb;
    float3 bloomColor = bloomTexture.sample(s, in.texCoord).rgb;
    float3 color = sceneColor + bloomColor * bloomStrength;
    if (isHDREnabled) {
        color = aces_tonemap(color);
    }
    color = pow(color, 1.0 / 2.2);
    color += postParams.x;
    color = (color - 0.5) * postParams.y + 0.5;
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = mix(float3(luma), color, postParams.z);
    color = saturate(color);
    return float4(color, 1.0);
}
