#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// One simulation iteration. The CPU schedules iterations at a fixed 60 Hz, so
// every encoded pass is a real step; frames 0-2 only initialise the state.
struct SimUniforms {
    int frame;
    int seedIndex;
    float dateSeconds;
    float padding;
};

// Per-frame constants for the final image, computed on the CPU in double
// precision: bubble wobble/breath/scroll as affine maps of screen uv, and the
// palette blend (formerly Buffer D's phase) as base and tint colours.
struct ImageUniforms {
    float4 coolTransform;
    float4 warmTransform;
    float4 bubbleOffset;
    float4 warmBase;
    float4 warmTint;
    float4 coolBase;
    float4 coolTint;
};

constant float2 SIM = float2(640.0, 360.0);
constant float2 TX = float2(1.0 / 640.0, 1.0 / 360.0);

vertex VertexOut fullscreenVertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * 0.5 + 0.5;
    return out;
}

struct ImageVertexOut {
    float4 position [[position]];
    float2 uv;
    float2 coolUV;
    float2 warmUV;
};

vertex ImageVertexOut imageVertex(uint vid [[vertex_id]], constant ImageUniforms& u [[buffer(0)]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    ImageVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * 0.5 + 0.5;
    // Both bubble layers are affine in uv, so interpolating them is exact.
    out.coolUV = float2x2(u.coolTransform.xy, u.coolTransform.zw) * out.uv + u.bubbleOffset.xy;
    out.warmUV = float2x2(u.warmTransform.xy, u.warmTransform.zw) * out.uv + u.bubbleOffset.zw;
    return out;
}

float4 readTex(texture2d<float> tex, int2 p) {
    if (tex.get_width() == 0) { return float4(0.0); }
    uint2 maxP = uint2(tex.get_width() - 1, tex.get_height() - 1);
    uint2 q = uint2(clamp(p, int2(0), int2(maxP)));
    return tex.read(q);
}

float4 cellRead(texture2d<float> tex, float2 c, float2 res) {
    float cx = fmod(c.x, SIM.x);
    if (cx < 0.0) { cx += SIM.x; }
    float cy = clamp(c.y, 0.0, SIM.y - 1.0);
    float scale = res.x * 0.0015625; // 1.0 / 640.0
    int2 px = int2((float2(cx, cy) + 0.5) * scale);
    return readTex(tex, px);
}

float4 field(texture2d<float> tex, float2 uv, float2 res) {
    float2 p = uv * SIM - 0.5;
    float2 i = floor(p);
    float2 f = fract(p);
    return mix(
        mix(cellRead(tex, i, res), cellRead(tex, i + float2(1.0, 0.0), res), f.x),
        mix(cellRead(tex, i + float2(0.0, 1.0), res), cellRead(tex, i + float2(1.0, 1.0), res), f.x),
        f.y
    );
}

float hash2(float2 p) {
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p + 34.5);
    return fract(p.x * p.y);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + float2(1.0, 0.0)), f.x),
        mix(hash2(i + float2(0.0, 1.0)), hash2(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * valueNoise(p);
        p = p * 2.0 + 1.7;
        a *= 0.5;
    }
    return v;
}

fragment float4 passA(VertexOut in [[stage_in]],
                      constant SimUniforms& u [[buffer(0)]],
                      texture2d<float> cPrev [[texture(0)]],
                      texture2d<float> seedTex [[texture(1)]],
                      sampler s [[sampler(0)]]) {
    float2 res = SIM;
    float2 uv = (floor(float2(in.uv.x, 1.0 - in.uv.y) * SIM) + 0.5) / SIM;

    if (u.frame < 3) {
        if (u.seedIndex < 6) {
            float4 val = seedTex.sample(s, float2(in.uv.x, 1.0 - in.uv.y));
            return float4(val.x, -val.y, val.z, val.w);
        }

        float dateW = u.dateSeconds;
        float2 r = float2(fract(dateW * 0.0173), fract(dateW * 0.0411)) * 53.0;
        float2 q = float2(uv.x * 1.7777, uv.y);
        float m = (uv.y - 0.5)
            + (fbm(q * 2.5 + r) - 0.5) * 0.8
            + (fbm(q * 6.0 + r * 1.7) - 0.5) * 0.8 * 0.45;
        float dye = (m > 0.0) ? 1.0 : -1.0;
        float e = 0.012;
        float2 vel = float2(
            fbm(q * 3.0 + r + float2(0.0, e)) - fbm(q * 3.0 + r - float2(0.0, e)),
            -(fbm(q * 3.0 + r + float2(e, 0.0)) - fbm(q * 3.0 + r - float2(e, 0.0)))
        ) / (2.0 * e);
        return float4(vel * 0.6, 0.0, dye);
    }

    float4 c = field(cPrev, uv, res);
    float pr = field(cPrev, uv + float2(TX.x, 0.0), res).z;
    float pu = field(cPrev, uv + float2(0.0, TX.y), res).z;
    float vx = c.x + (c.z - pr);
    float vy = c.y + (c.z - pu);
    vy += -c.w * 0.002656;
    vx *= 0.998;
    vy *= 0.998;

    float inj = 0.00125 + (min(uv.y, 1.0 - uv.y) < 0.01 ? 0.0003 : 0.0);
    float dye = c.w;
    if (uv.y > 0.55) { dye += inj; }
    else if (uv.y < 0.45) { dye -= inj; }
    dye = clamp(dye, -1.0, 1.0);
    if (min(uv.y, 1.0 - uv.y) < TX.y) { vy = 0.0; }
    return float4(vx, vy, c.z, dye);
}

fragment float4 passB(VertexOut in [[stage_in]],
                      constant SimUniforms& u [[buffer(0)]],
                      texture2d<float> aTex [[texture(0)]]) {
    float2 res = SIM;
    float2 uv = (floor(float2(in.uv.x, 1.0 - in.uv.y) * SIM) + 0.5) / SIM;
    if (u.frame < 3) { return readTex(aTex, int2(float2(in.uv.x, 1.0 - in.uv.y) * res)); }

    float4 c = field(aTex, uv, res);
    float lx = field(aTex, uv - float2(TX.x, 0.0), res).x;
    float dy = field(aTex, uv - float2(0.0, TX.y), res).y;
    float negDiv = (lx - c.x) + (dy - c.y);
    return float4(c.x, c.y, c.z + 0.5 * negDiv, c.w);
}

struct PassCOut {
    float4 state [[color(0)]];
    // Dye only, so the full-resolution image pass samples a 4-byte texel
    // instead of the 16-byte simulation state.
    float dye [[color(1)]];
};

fragment PassCOut passC(VertexOut in [[stage_in]],
                        constant SimUniforms& u [[buffer(0)]],
                        texture2d<float> bTex [[texture(0)]]) {
    float2 res = SIM;
    float2 uv = (floor(float2(in.uv.x, 1.0 - in.uv.y) * SIM) + 0.5) / SIM;
    PassCOut out;
    if (u.frame < 3) {
        out.state = readTex(bTex, int2(float2(in.uv.x, 1.0 - in.uv.y) * res));
    } else {
        float2 vel = field(bTex, uv, res).xy;
        out.state = field(bTex, uv - vel * TX, res);
    }
    out.dye = out.state.w;
    return out;
}

constexpr sampler bubbleSampler(address::repeat, filter::linear);
constexpr sampler dyeSampler(s_address::repeat, t_address::clamp_to_edge, filter::linear);

fragment float4 imagePass(ImageVertexOut in [[stage_in]],
                          constant ImageUniforms& u [[buffer(0)]],
                          texture2d<float> dyeTex [[texture(0)]],
                          texture2d<float> bubbleTex [[texture(1)]]) {
    float2 uv = in.uv;
    float2 br = 0.5 / SIM;
    float dye = (dyeTex.sample(dyeSampler, uv).x * 2.0
        + dyeTex.sample(dyeSampler, uv + float2(br.x, 0.0)).x
        + dyeTex.sample(dyeSampler, uv - float2(br.x, 0.0)).x
        + dyeTex.sample(dyeSampler, uv + float2(0.0, br.y)).x
        + dyeTex.sample(dyeSampler, uv - float2(0.0, br.y)).x) / 6.0;
    float a = clamp(dye * 248.659 - 48.757, 0.0, 1.0);

    float bb = bubbleTex.sample(bubbleSampler, in.coolUV).x;
    float bo = bubbleTex.sample(bubbleSampler, in.warmUV).x;
    float3 warmC = u.warmBase.xyz + bo * u.warmTint.xyz;
    float3 coolC = u.coolBase.xyz + bb * u.coolTint.xyz;
    return float4(mix(coolC, warmC, a), 1.0);
}
