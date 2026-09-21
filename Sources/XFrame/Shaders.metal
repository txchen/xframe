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

fragment float4 videoFragment(VertexOutput in [[stage_in]],
                              texture2d<float> luma [[texture(0)]],
                              texture2d<float> chroma [[texture(1)]],
                              constant float4 &conversion [[buffer(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float y = (luma.sample(linearSampler, in.uv).r * 255.0 - 16.0) / 219.0;
    float2 cbcr = (chroma.sample(linearSampler, in.uv).rg * 255.0 - 128.0) / 224.0;
    float kr = conversion.x, kb = conversion.y, kg = 1.0 - kr - kb;
    float r = y + 2.0 * (1.0 - kr) * cbcr.y;
    float b = y + 2.0 * (1.0 - kb) * cbcr.x;
    float g = y - 2.0 * kb * (1.0 - kb) / kg * cbcr.x - 2.0 * kr * (1.0 - kr) / kg * cbcr.y;
    return float4(saturate(float3(r, g, b)), 1.0);
}
