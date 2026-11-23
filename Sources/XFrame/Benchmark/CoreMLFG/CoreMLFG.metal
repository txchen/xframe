#include <metal_stdlib>
using namespace metal;

struct FGSize {
    uint w, h, pw, ph, scale;
};

struct FGBias {
    half b0[8];
    half b1[8];
};

constexpr sampler linearPixel(coord::pixel, address::clamp_to_edge, filter::linear);

// Sample the box area mean of RGB8 texels. Padded tile gutter stays zero.
float3 fgBox(texture2d<float> t, int2 p, constant FGSize& s) {
    if (any(p >= int2(s.w / s.scale, s.h / s.scale))) return 0;
    if (s.scale == 2) return t.sample(linearPixel, float2(2 * p) + 1.f).rgb;
    // Exact 3x3 area mean using four bilinear taps.
    float2 q = float2(3 * p);
    float3 sum = 0;
    for (int j = 0; j < 2; j++) {
        for (int i = 0; i < 2; i++) {
            sum += t.sample(linearPixel, q + float2(i ? 2.5f : 1.f, j ? 2.5f : 1.f)).rgb
                 * float((i ? 1 : 2) * (j ? 1 : 2));
        }
    }
    return sum / 9.f;
}

kernel void fgCandidates(texture2d<float> a, texture2d<float> b, device half* out,
                         constant FGSize& s, uint2 p [[thread_position_in_grid]]) {
    if (p.x >= s.pw || p.y >= s.ph) return;
    float e = 0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            int2 q = clamp(int2(p) + int2(i, j), int2(0), int2(s.pw - 1, s.ph - 1));
            e += dot(abs(fgBox(a, q, s) - fgBox(b, q, s)), float3(1.f / 3))
               * ((i == 0) ? .75 : .125) * ((j == 0) ? .75 : .125);
        }
    }
    out += (p.y * s.pw + p.x) * 16;
    half3 ca = half3(fgBox(a, int2(p), s));
    half3 cb = half3(fgBox(b, int2(p), s));
    for (uint c = 0; c < 3; c++) {
        out[c] = ca[c];
        out[4 + c] = cb[c];
    }
    out[3] = out[7] = e;
    out[8] = 0;
    out[9] = .5h;
    for (uint c = 10; c < 16; c++) out[c] = 0;
}

float fgSamplePlane(device const half* t, int w, int h, int stride, int c, float2 p, bool applySigmoid = false) {
    float2 pos = clamp(p, float2(0), float2(w - 1, h - 1));
    float2 f = fract(pos);
    int2 lo = int2(pos);
    int2 hi = min(lo + 1, int2(w - 1, h - 1));
    auto get = [&](int x, int y) {
        float v = t[(y * w + x) * stride + c];
        return applySigmoid ? 1.f / (1.f + exp(-v)) : v;
    };
    return mix(mix(get(lo.x, lo.y), get(hi.x, lo.y), f.x),
               mix(get(lo.x, hi.y), get(hi.x, hi.y), f.x), f.y);
}

kernel void fgFeatures(device const half* cand, device const half* coarse, device half* out,
                       constant FGSize& s, constant FGBias& bias, uint2 p [[thread_position_in_grid]]) {
    if (p.x >= s.pw || p.y >= s.ph) return;
    float up[8];
    for (int c = 0; c < 8; c++) {
        up[c] = fgSamplePlane(coarse, s.pw / 2, s.ph / 2, 8, c, (float2(p) + .5f) * .5f - .5f)
              + float(bias.b0[c]);
    }
    out += (p.y * s.pw + p.x) * 18;
    for (int c = 0; c < 8; c++) {
        int k = (c / 4) * 2;
        out[c] = fgSamplePlane(cand, s.pw, s.ph, 16, c, float2(p) + 2.f * float2(up[k], up[k + 1]));
    }
    for (int c = 0; c < 5; c++) out[8 + c] = up[c];
    out[13] = 0;
    for (int c = 5; c < 8; c++) out[9 + c] = up[c];
    out[17] = .5h;
}

kernel void fgCoarseOnly(device const half* coarse, device half* field,
                         constant FGSize& s, constant FGBias& bias, uint2 p [[thread_position_in_grid]]) {
    if (p.x >= s.pw || p.y >= s.ph) return;
    for (int c = 0; c < 5; c++) {
        float v = fgSamplePlane(coarse, s.pw / 2, s.ph / 2, 8, c, (float2(p) + .5f) * .5f - .5f)
                + float(bias.b0[c]);
        field[(p.y * s.pw + p.x) * 5 + c] = v * (c == 4 ? 1.f : 2.f);
    }
}

kernel void fgMergeFields(device const half* feat, device const half* fine, device half* field,
                          constant FGSize& s, constant FGBias& bias, uint2 p [[thread_position_in_grid]]) {
    if (p.x >= s.pw || p.y >= s.ph) return;
    uint i = p.y * s.pw + p.x;
    for (int c = 0; c < 5; c++) {
        field[i * 5 + c] = feat[i * 18 + 8 + c] * (c == 4 ? 1.h : 2.h) + fine[i * 8 + c] + bias.b1[c];
    }
}

kernel void fgCompose(texture2d<float> a, texture2d<float> b, texture2d<float, access::write> out,
                      device const half* field, constant FGSize& s, uint2 p [[thread_position_in_grid]]) {
    if (p.x >= s.w || p.y >= s.h) return;
    float v[5];
    for (int c = 0; c < 5; c++) {
        v[c] = fgSamplePlane(field, s.pw, s.ph, 5, c, float2(p) / float(s.scale), c == 4);
    }
    float2 center = float2(p) + .5f;
    out.write(mix(b.sample(linearPixel, center + float(s.scale) * float2(v[2], v[3])),
                  a.sample(linearPixel, center + float(s.scale) * float2(v[0], v[1])), v[4]), p);
}
