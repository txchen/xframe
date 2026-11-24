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

// AMD FSR 1 EASU (Edge-Adaptive Spatial Upsampling) over NV12 video planes.
static inline float fsrLuma(float3 c) { return c.b * 0.5 + (c.r * 0.5 + c.g); }

static inline void fsrEasuSet(thread float2 &dir, thread float &len, float2 pp,
                              bool biS, bool biT, bool biU, bool biV,
                              float lA, float lB, float lC, float lD, float lE) {
    float w = 0.0;
    if (biS) w = (1.0 - pp.x) * (1.0 - pp.y);
    if (biT) w = pp.x * (1.0 - pp.y);
    if (biU) w = (1.0 - pp.x) * pp.y;
    if (biV) w = pp.x * pp.y;
    float dc = lD - lC;
    float cb = lC - lB;
    float lenX = max(abs(dc), abs(cb));
    lenX = lenX > 1e-5 ? 1.0 / lenX : 0.0;
    float dirX = lD - lB;
    dir.x += dirX * w;
    lenX = saturate(abs(dirX) * lenX);
    lenX *= lenX;
    len += lenX * w;
    float ec = lE - lC;
    float ca = lC - lA;
    float lenY = max(abs(ec), abs(ca));
    lenY = lenY > 1e-5 ? 1.0 / lenY : 0.0;
    float dirY = lE - lA;
    dir.y += dirY * w;
    lenY = saturate(abs(dirY) * lenY);
    lenY *= lenY;
    len += lenY * w;
}

static inline void fsrEasuTap(thread float3 &aC, thread float &aW, float2 off, float2 dir,
                              float2 len, float lob, float clp, float3 c) {
    float2 v = float2(off.x * dir.x + off.y * dir.y, off.x * (-dir.y) + off.y * dir.x);
    v *= len;
    float d2 = min(dot(v, v), clp);
    float wB = 0.4 * d2 - 1.0;
    float wA = lob * d2 - 1.0;
    wB *= wB;
    wA *= wA;
    wB = (25.0 / 16.0) * wB - (9.0 / 16.0);
    float w = wB * wA;
    aC += c * w;
    aW += w;
}

fragment float4 fsr1EasuVideoFragment(VertexOutput in [[stage_in]],
                                      texture2d<float> luma [[texture(0)]],
                                      texture2d<float> chroma [[texture(1)]],
                                      constant float4 &conversion [[buffer(0)]]) {
    float2 srcSize = float2(luma.get_width(), luma.get_height());
    float2 invSize = 1.0 / srcSize;
    float2 pp = in.uv * srcSize - 0.5;
    float2 fp = floor(pp);
    pp -= fp;

    auto fetch = [&](float2 o) -> float3 {
        return videoColor((fp + o + 0.5) * invSize, luma, chroma, conversion).rgb;
    };

    // 12-tap EASU cross footprint around the target sample.
    float3 b = fetch(float2( 0, -1));
    float3 c = fetch(float2( 1, -1));
    float3 e = fetch(float2(-1,  0));
    float3 f = fetch(float2( 0,  0));
    float3 g = fetch(float2( 1,  0));
    float3 h = fetch(float2( 2,  0));
    float3 i = fetch(float2(-1,  1));
    float3 j = fetch(float2( 0,  1));
    float3 k = fetch(float2( 1,  1));
    float3 l = fetch(float2( 2,  1));
    float3 n = fetch(float2( 0,  2));
    float3 o = fetch(float2( 1,  2));

    float bL = fsrLuma(b), cL = fsrLuma(c), eL = fsrLuma(e), fL = fsrLuma(f);
    float gL = fsrLuma(g), hL = fsrLuma(h), iL = fsrLuma(i), jL = fsrLuma(j);
    float kL = fsrLuma(k), lL = fsrLuma(l), nL = fsrLuma(n), oL = fsrLuma(o);

    float2 dir = float2(0.0);
    float len = 0.0;
    fsrEasuSet(dir, len, pp, true,  false, false, false, bL, eL, fL, gL, jL);
    fsrEasuSet(dir, len, pp, false, true,  false, false, cL, fL, gL, hL, kL);
    fsrEasuSet(dir, len, pp, false, false, true,  false, fL, iL, jL, kL, nL);
    fsrEasuSet(dir, len, pp, false, false, false, true,  gL, jL, kL, lL, oL);

    float dirR = dot(dir, dir);
    bool zro = dirR < (1.0 / 32768.0);
    dir = zro ? float2(1.0, 0.0) : dir * rsqrt(dirR);
    len = len * 0.5;
    len *= len;
    float stretch = (dir.x * dir.x + dir.y * dir.y) / max(abs(dir.x), abs(dir.y));
    float2 len2 = float2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len);
    float lob = 0.5 + ((1.0 / 4.0 - 0.04) - 0.5) * len;
    float clp = 1.0 / lob;

    float3 min4 = min(min(f, g), min(j, k));
    float3 max4 = max(max(f, g), max(j, k));
    float3 aC = float3(0.0);
    float aW = 0.0;
    fsrEasuTap(aC, aW, float2( 0, -1) - pp, dir, len2, lob, clp, b);
    fsrEasuTap(aC, aW, float2( 1, -1) - pp, dir, len2, lob, clp, c);
    fsrEasuTap(aC, aW, float2(-1,  0) - pp, dir, len2, lob, clp, e);
    fsrEasuTap(aC, aW, float2( 0,  0) - pp, dir, len2, lob, clp, f);
    fsrEasuTap(aC, aW, float2( 1,  0) - pp, dir, len2, lob, clp, g);
    fsrEasuTap(aC, aW, float2( 2,  0) - pp, dir, len2, lob, clp, h);
    fsrEasuTap(aC, aW, float2(-1,  1) - pp, dir, len2, lob, clp, i);
    fsrEasuTap(aC, aW, float2( 0,  1) - pp, dir, len2, lob, clp, j);
    fsrEasuTap(aC, aW, float2( 1,  1) - pp, dir, len2, lob, clp, k);
    fsrEasuTap(aC, aW, float2( 2,  1) - pp, dir, len2, lob, clp, l);
    fsrEasuTap(aC, aW, float2( 0,  2) - pp, dir, len2, lob, clp, n);
    fsrEasuTap(aC, aW, float2( 1,  2) - pp, dir, len2, lob, clp, o);

    float3 result = clamp(aC / max(aW, 1e-5), min4, max4);
    return float4(saturate(result), 1.0);
}

// AMD FSR 1 RCAS (Robust Contrast-Adaptive Sharpening) pass.
fragment float4 fsr1RcasFragment(VertexOutput in [[stage_in]],
                                 texture2d<float> image [[texture(0)]],
                                 constant float &sharpness [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 px = 1.0 / float2(image.get_width(), image.get_height());
    float3 e = image.sample(s, in.uv).rgb;
    float3 b = image.sample(s, in.uv + float2(0, -px.y)).rgb;
    float3 d = image.sample(s, in.uv + float2(-px.x, 0)).rgb;
    float3 f = image.sample(s, in.uv + float2(px.x, 0)).rgb;
    float3 h = image.sample(s, in.uv + float2(0, px.y)).rgb;

    float bL = fsrLuma(b), dL = fsrLuma(d), eL = fsrLuma(e), fL = fsrLuma(f), hL = fsrLuma(h);
    float mn4L = min(min(bL, dL), min(fL, hL));
    float mx4L = max(max(bL, dL), max(fL, hL));
    float hitMin = min(mn4L, eL) / max(4.0 * mx4L, 1e-5);
    float hitMax = (1.0 - max(mx4L, eL)) / max(4.0 * mn4L - 4.0, -1e-5);
    float lobe = max(-hitMin, hitMax);
    float w = clamp(lobe, -0.1875, 0.0) * clamp(sharpness, 0.0, 1.0);
    float3 outRGB = (w * (b + d + f + h) + e) / (4.0 * w + 1.0);
    return float4(saturate(outRGB), 1.0);
}
