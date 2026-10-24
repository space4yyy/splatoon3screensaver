#include <metal_stdlib>
using namespace metal;

// One simulation iteration. The CPU schedules iterations at a fixed 60 Hz, so
// every dispatched step is a real step; frames 0-2 only initialise the state.
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

// The image blurs the dye with five bilinear taps half a texel apart. That
// blur is itself bilinear between the knots of a half-texel lattice, so
// passKnots evaluates it once per step at 1280 x 721 knots, knot (m, n) at dye
// uv (m / 1280, n / 720), and the image samples it once per pixel.
constant float2 KNOTS = float2(1280.0, 720.0);

struct ImageVertexOut {
    float4 position [[position]];
    float2 knotUV;
    float2 coolUV;
    float2 warmUV;
};

vertex ImageVertexOut imageVertex(uint vid [[vertex_id]], constant ImageUniforms& u [[buffer(0)]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    ImageVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    float2 uv = positions[vid] * 0.5 + 0.5;
    // Knot (m, n) is the centre of texel (m, n) of the knot texture.
    out.knotUV = float2(uv.x + 0.5 / KNOTS.x, (uv.y * KNOTS.y + 0.5) / (KNOTS.y + 1.0));
    // Both bubble layers are affine in uv, so interpolating them is exact.
    out.coolUV = float2x2(u.coolTransform.xy, u.coolTransform.zw) * uv + u.bubbleOffset.xy;
    out.warmUV = float2x2(u.warmTransform.xy, u.warmTransform.zw) * uv + u.bubbleOffset.zw;
    return out;
}

// Simulation texel c, wrapping in x and clamping in y like the original's
// buffer reads.
float4 cell(texture2d<float> tex, int2 c) {
    int x = c.x % 640;
    if (x < 0) { x += 640; }
    return tex.read(uint2(x, clamp(c.y, 0, 359)));
}

// Bilinear interpolation of the simulation state at p, in texels, where
// integer coordinates are texel centres.
float4 field(texture2d<float> tex, float2 p) {
    float2 i = floor(p);
    float2 f = p - i;
    int2 c = int2(i);
    return mix(
        mix(cell(tex, c), cell(tex, c + int2(1, 0)), f.x),
        mix(cell(tex, c + int2(0, 1)), cell(tex, c + int2(1, 1)), f.x),
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

// The simulation passes run one thread per texel. Texel row 0 holds the
// original's bottom row, so every pass reads and writes the same rows and the
// image's uv addresses them directly.

kernel void passA(texture2d<float> cPrev [[texture(0)]],
                  texture2d<float> seedTex [[texture(1)]],
                  texture2d<float, access::write> outA [[texture(2)]],
                  constant SimUniforms& u [[buffer(0)]],
                  uint2 gid [[thread_position_in_grid]]) {
    constexpr sampler seedSampler(filter::linear, address::clamp_to_edge);
    int2 id = int2(gid);
    float2 uv = (float2(gid) + 0.5) / SIM;

    if (u.frame < 3) {
        if (u.seedIndex < 6) {
            float4 val = seedTex.sample(seedSampler, uv, level(0));
            outA.write(float4(val.x, -val.y, val.z, val.w), gid);
            return;
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
        outA.write(float4(vel * 0.6, 0.0, dye), gid);
        return;
    }

    float4 c = cell(cPrev, id);
    float pr = cell(cPrev, id + int2(1, 0)).z;
    float pu = cell(cPrev, id + int2(0, 1)).z;
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
    outA.write(float4(vx, vy, c.z, dye), gid);
}

kernel void passB(texture2d<float> aTex [[texture(0)]],
                  texture2d<float, access::write> outB [[texture(1)]],
                  constant SimUniforms& u [[buffer(0)]],
                  uint2 gid [[thread_position_in_grid]]) {
    int2 id = int2(gid);
    float4 c = cell(aTex, id);
    if (u.frame >= 3) {
        float lx = cell(aTex, id - int2(1, 0)).x;
        float dy = cell(aTex, id - int2(0, 1)).y;
        float negDiv = (lx - c.x) + (dy - c.y);
        c.z += 0.5 * negDiv;
    }
    outB.write(c, gid);
}

// Also writes the dye on its own, so passKnots reads 4-byte texels instead of
// the 16-byte state.
kernel void passC(texture2d<float> bTex [[texture(0)]],
                  texture2d<float, access::write> outC [[texture(1)]],
                  texture2d<float, access::write> outDye [[texture(2)]],
                  constant SimUniforms& u [[buffer(0)]],
                  uint2 gid [[thread_position_in_grid]]) {
    int2 id = int2(gid);
    float4 state = cell(bTex, id);
    if (u.frame >= 3) {
        state = field(bTex, float2(id) - state.xy);
    }
    outC.write(state, gid);
    outDye.write(float4(state.w), gid);
}

// Thread (i, j) writes knots (2i, 2j) to (2i + 1, 2j + 1) from the 3 x 3 dye
// texels around texel (i, j): the image's five taps at a knot land on texel
// centres and edges, so each is an exact average of one, two or four texels.
kernel void passKnots(texture2d<float> dye [[texture(0)]],
                      texture2d<float, access::write> knots [[texture(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
    int i = int(gid.x);
    int j = int(gid.y);
    uint il = uint((i + 639) % 640), ic = uint(i), ir = uint((i + 1) % 640);
    uint jd = uint(max(j - 1, 0)), jc = uint(min(j, 359)), ju = uint(min(j + 1, 359));
    float dl = dye.read(uint2(il, jd)).x, dc = dye.read(uint2(ic, jd)).x, dr = dye.read(uint2(ir, jd)).x;
    float cl = dye.read(uint2(il, jc)).x, cc = dye.read(uint2(ic, jc)).x, cr = dye.read(uint2(ir, jc)).x;
    float ul = dye.read(uint2(il, ju)).x, uc = dye.read(uint2(ic, ju)).x;
    uint2 k = gid * 2;
    // Between four texel centres.
    knots.write(float4(0.25 * (dl + dc + cl + cc)), k);
    // Between two texel centres in y.
    knots.write(float4((2.5 * (dc + cc) + 0.25 * (dl + cl + dr + cr)) / 6.0), k + uint2(1, 0));
    // The last row of knots lies on the top edge and has no odd row.
    if (j < 360) {
        // Between two texel centres in x.
        knots.write(float4((2.5 * (cl + cc) + 0.25 * (ul + uc + dl + dc)) / 6.0), k + uint2(0, 1));
        // On a texel centre.
        knots.write(float4((4.0 * cc + 0.5 * (cl + cr + dc + uc)) / 6.0), k + uint2(1, 1));
    }
}

constexpr sampler bubbleSampler(address::repeat, filter::linear);
constexpr sampler knotSampler(s_address::repeat, t_address::clamp_to_edge, filter::linear);

fragment float4 imagePass(ImageVertexOut in [[stage_in]],
                          constant ImageUniforms& u [[buffer(0)]],
                          texture2d<float> knotTex [[texture(0)]],
                          texture2d<float> bubbleTex [[texture(1)]]) {
    float dye = knotTex.sample(knotSampler, in.knotUV).x;
    float a = clamp(dye * 248.659 - 48.757, 0.0, 1.0);

    float bb = bubbleTex.sample(bubbleSampler, in.coolUV).x;
    float bo = bubbleTex.sample(bubbleSampler, in.warmUV).x;
    float3 warmC = u.warmBase.xyz + bo * u.warmTint.xyz;
    float3 coolC = u.coolBase.xyz + bb * u.coolTint.xyz;
    return float4(mix(coolC, warmC, a), 1.0);
}
