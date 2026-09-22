#include <metal_stdlib>
using namespace metal;

struct VertexOutput {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOutput patternVertex(uint id [[vertex_id]]) {
    const float2 positions[] = {float2(-1, 1), float2(-1, -1), float2(1, 1), float2(1, -1)};
    const float2 coordinates[] = {float2(0, 0), float2(0, 1), float2(1, 0), float2(1, 1)};
    return {float4(positions[id], 0, 1), coordinates[id]};
}

fragment float4 patternFragment(VertexOutput in [[stage_in]], texture2d<float> pattern [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return pattern.sample(linearSampler, in.uv);
}

fragment float4 nearestFragment(VertexOutput in [[stage_in]], texture2d<float> image [[texture(0)]]) {
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    return image.sample(nearestSampler, in.uv);
}

float4 videoColor(float2 uv, texture2d<float> luma, texture2d<float> chroma, float4 conversion) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float y = (luma.sample(linearSampler, uv).r * 255.0 - 16.0) / 219.0;
    float2 cbcr = (chroma.sample(linearSampler, uv).rg * 255.0 - 128.0) / 224.0;
    float kr = conversion.x, kb = conversion.y, kg = 1.0 - kr - kb;
    float r = y + 2.0 * (1.0 - kr) * cbcr.y;
    float b = y + 2.0 * (1.0 - kb) * cbcr.x;
    float g = y - 2.0 * kb * (1.0 - kb) / kg * cbcr.x - 2.0 * kr * (1.0 - kr) / kg * cbcr.y;
    return float4(saturate(float3(r, g, b)), 1.0);
}

fragment float4 videoFragment(VertexOutput in [[stage_in]],
                              texture2d<float> luma [[texture(0)]],
                              texture2d<float> chroma [[texture(1)]],
                              constant float4 &conversion [[buffer(0)]]) {
    return videoColor(in.uv, luma, chroma, conversion);
}

fragment float4 integerVideoFragment(VertexOutput in [[stage_in]],
                                     texture2d<float> luma [[texture(0)]],
                                     texture2d<float> chroma [[texture(1)]],
                                     constant float4 &conversion [[buffer(0)]]) {
    float2 extent = float2(luma.get_width(), luma.get_height());
    // Reconstruct chroma at the source pixel center, then replicate that color.
    // Merely switching the luma sampler would still interpolate inside each block.
    float2 center = (floor(in.uv * extent) + 0.5) / extent;
    return videoColor(center, luma, chroma, conversion);
}

// Restrained luminance unsharp mask on the upscaled image. The symmetric kernel
// preserves flat fields; the bounded correction limits ringing/compression noise.
// Fused into final composition so sharpening adds no frame queue or intermediate.
fragment float4 sharpenFragment(VertexOutput in [[stage_in]],
                                texture2d<float> image [[texture(0)]],
                                constant float &amount [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 center = image.sample(s, in.uv);
    float2 pixel = 1.0 / float2(image.get_width(), image.get_height());
    float3 neighbors = (image.sample(s, in.uv + float2(pixel.x, 0)).rgb
                      + image.sample(s, in.uv - float2(pixel.x, 0)).rgb
                      + image.sample(s, in.uv + float2(0, pixel.y)).rgb
                      + image.sample(s, in.uv - float2(0, pixel.y)).rgb) * 0.25;
    const float3 luma = float3(0.2126, 0.7152, 0.0722);
    float detail = clamp(dot(center.rgb - neighbors, luma), -0.08, 0.08);
    return float4(saturate(center.rgb + detail * amount), center.a);
}
