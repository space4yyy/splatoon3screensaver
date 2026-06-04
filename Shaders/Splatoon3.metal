#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float4 resolution;
    float4 bufferResolution;
    float4 mouse;
    float4 customWarm;
    float4 customCool;
    int4 state;
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
    int2 px = int2((float2(cx, cy) + 0.5) / SIM * res);
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
                      constant Uniforms& u [[buffer(0)]],
                      texture2d<float> cPrev [[texture(0)]]) {
    float2 res = u.resolution.xy;
    float2 uv = (floor(float2(in.uv.x, 1.0 - in.uv.y) * SIM) + 0.5) / SIM;
    float time = u.bufferResolution.w;
    float timeDelta = u.customWarm.w;
    float dateW = u.customCool.w;
    int frame = u.state.x;
    float rate = 60.0 * (time < 0.6 ? 12.0 : 1.0);

    if (frame < 3) {
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

    bool simStep = (frame >= 3) && (floor(time * rate) != floor((time - timeDelta) * rate));
    if (!simStep) {
        return field(cPrev, uv, res);
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
                      constant Uniforms& u [[buffer(0)]],
                      texture2d<float> aTex [[texture(0)]]) {
    float2 res = u.resolution.xy;
    float2 uv = (floor(float2(in.uv.x, 1.0 - in.uv.y) * SIM) + 0.5) / SIM;
    float time = u.bufferResolution.w;
    float timeDelta = u.customWarm.w;
    int frame = u.state.x;
    float rate = 60.0 * (time < 0.5 ? 15.0 : 1.0);
    bool simStep = (frame >= 3) && (floor(time * rate) != floor((time - timeDelta) * rate));
    if (!simStep) { return field(aTex, uv, res); }

    float4 c = field(aTex, uv, res);
    float lx = field(aTex, uv - float2(TX.x, 0.0), res).x;
    float dy = field(aTex, uv - float2(0.0, TX.y), res).y;
    float negDiv = (lx - c.x) + (dy - c.y);
    return float4(c.x, c.y, c.z + 0.5 * negDiv, c.w);
}

fragment float4 passC(VertexOut in [[stage_in]],
                      constant Uniforms& u [[buffer(0)]],
                      texture2d<float> bTex [[texture(0)]]) {
    float2 res = u.resolution.xy;
    float2 uv = (floor(float2(in.uv.x, 1.0 - in.uv.y) * SIM) + 0.5) / SIM;
    float time = u.bufferResolution.w;
    float timeDelta = u.customWarm.w;
    int frame = u.state.x;
    float rate = 60.0 * (time < 0.5 ? 15.0 : 1.0);
    bool simStep = (frame >= 3) && (floor(time * rate) != floor((time - timeDelta) * rate));
    if (!simStep) { return field(bTex, uv, res); }
    float2 vel = field(bTex, uv, res).xy;
    return field(bTex, uv - vel * TX, res);
}

fragment float4 passD(VertexOut in [[stage_in]],
                      constant Uniforms& u [[buffer(0)]],
                      texture2d<float> dPrev [[texture(0)]],
                      texture2d<float> bubble [[texture(1)]]) {
    int2 p = int2(float2(in.uv.x, 1.0 - in.uv.y) * u.resolution.xy);
    if (p.x < 256 && p.y < 128) {
        if (u.state.x < 1) { return float4(bubble.read(uint2(p)).x); }
        return readTex(dPrev, p);
    }

    float4 s = readTex(dPrev, int2(256, 0));
    float phase = s.x;
    float target = s.y;
    float prevDown = s.z;

    if (u.state.y == 1) {
        // Auto-cycling mode: animate phase based on absolute time
        float time = u.bufferResolution.w;
        float T = 30.0; // cycle interval (30 seconds per game)
        float t_trans = 4.0; // transition duration (4 seconds)
        float cycleIndex = floor(time / T);
        float rem = fmod(time, T);
        if (rem < T - t_trans) {
            phase = cycleIndex;
        } else {
            phase = cycleIndex + (rem - (T - t_trans)) / t_trans;
        }
        target = phase;
        prevDown = 0.0;
    } else {
        // Locked color modes
        if (u.state.y == 2) { phase = 1.0; } // Splatoon 1
        else if (u.state.y == 3) { phase = 2.0; } // Splatoon 2
        else { phase = 0.0; } // Splatoon 3 (mode 4) and Custom (mode 5)
        target = phase;
        prevDown = 0.0;
    }
    return float4(phase, target, prevDown, 1.0);
}

float2x2 rot(float a) {
    float c = cos(a);
    float s = sin(a);
    return float2x2(float2(c, -s), float2(s, c));
}

float coolWob(float p) {
    return p < 0.3265 ? mix(0.0, 1.58748, smoothstep(0.0, 0.3265, p))
                      : mix(1.58748, 0.0, smoothstep(0.3265, 1.0, p));
}

float warmWob(float p) {
    if (p < 0.2695) { return mix(0.0, -9.0, smoothstep(0.0, 0.2695, p)); }
    if (p < 0.6435) { return mix(-9.0, 12.0, smoothstep(0.2695, 0.6435, p)); }
    return mix(12.0, 0.0, smoothstep(0.6435, 1.0, p));
}

float coolBreath(float fr) {
    float lf = fmod(fr, 400.0);
    float s = lf < 226.0 ? smoothstep(0.0, 226.0, lf) : 1.0 - smoothstep(226.0, 400.0, lf);
    return mix(1.0, 2.30 / 2.24722, s);
}

float warmBreathX(float fr) {
    float lf = fmod(fr, 500.0);
    float s = lf < 118.0 ? smoothstep(0.0, 118.0, lf) : 1.0 - smoothstep(118.0, 500.0, lf);
    return mix(1.0, 0.52037 / 0.5, s);
}

float warmBreathY(float fr) {
    float lf = fmod(fr, 500.0);
    float s = lf < 351.0 ? smoothstep(0.0, 351.0, lf) : 1.0 - smoothstep(351.0, 500.0, lf);
    return mix(1.0, 0.52037 / 0.5, s);
}

float3 toSRGB(float3 c) {
    c = clamp(c, 0.0, 1.0);
    return mix(12.92 * c, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(float3(0.0031308), c));
}

float bubbleTex(texture2d<float> dTex, float2 pp) {
    float2 t = fract(pp) * float2(256.0, 128.0) - 0.5;
    int2 i = int2(floor(t));
    float2 f = fract(t);
    float a = readTex(dTex, int2(i.x & 255, i.y & 127)).x;
    float b = readTex(dTex, int2((i.x + 1) & 255, i.y & 127)).x;
    float c = readTex(dTex, int2(i.x & 255, (i.y + 1) & 127)).x;
    float d = readTex(dTex, int2((i.x + 1) & 255, (i.y + 1) & 127)).x;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float dyeAt(texture2d<float> cTex, float2 uv, float2 res) {
    float2 p = uv * SIM - 0.5;
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(cellRead(cTex, i, res).w, cellRead(cTex, i + float2(1.0, 0.0), res).w, f.x),
        mix(cellRead(cTex, i + float2(0.0, 1.0), res).w, cellRead(cTex, i + float2(1.0, 1.0), res).w, f.x),
        f.y
    );
}

float3 paletteWarm(int idx, constant Uniforms& u) {
    int mode = u.state.y;
    if (mode == 5) { return u.customWarm.xyz; }
    if (mode == 2) { return float3(0.945098, 0.098039, 0.0); } // Splatoon 1 (Orange)
    if (mode == 3) { return float3(0.980392, 0.054902, 0.470588); } // Splatoon 2 (Pink)
    if (mode == 4) { return float3(0.729412, 1.0, 0.039216); } // Splatoon 3 (Yellow)
    
    // mode == 1 (Cycle)
    if (idx == 1) { return float3(0.945098, 0.098039, 0.0); }
    if (idx == 2) { return float3(0.980392, 0.054902, 0.470588); }
    return float3(0.729412, 1.0, 0.039216);
}

float3 paletteCool(int idx, constant Uniforms& u) {
    int mode = u.state.y;
    if (mode == 5) { return u.customCool.xyz; }
    if (mode == 2) { return float3(0.0, 0.027451, 0.956863); } // Splatoon 1 (Blue)
    if (mode == 3) { return float3(0.039216, 0.921569, 0.031373); } // Splatoon 2 (Green)
    if (mode == 4) { return float3(0.113725, 0.039216, 1.0); } // Splatoon 3 (Purple)
    
    // mode == 1 (Cycle)
    if (idx == 1) { return float3(0.0, 0.027451, 0.956863); }
    if (idx == 2) { return float3(0.039216, 0.921569, 0.031373); }
    return float3(0.113725, 0.039216, 1.0);
}

fragment float4 imagePass(VertexOut in [[stage_in]],
                          constant Uniforms& u [[buffer(0)]],
                          texture2d<float> cTex [[texture(0)]],
                          texture2d<float> dTex [[texture(2)]]) {
    float2 R = u.resolution.xy;
    float2 bufferR = u.bufferResolution.xy;
    float2 uv = in.uv;
    float phase = readTex(dTex, int2(256, 0)).x;
    int from = int(fmod(floor(phase), 3.0));
    int to = int(fmod(floor(phase) + 1.0, 3.0));
    float tt = smoothstep(0.0, 1.0, fract(phase));

    float2 br = 0.5 / SIM;
    float dye = (dyeAt(cTex, uv, bufferR) * 2.0
        + dyeAt(cTex, uv + float2(br.x, 0.0), bufferR)
        + dyeAt(cTex, uv - float2(br.x, 0.0), bufferR)
        + dyeAt(cTex, uv + float2(0.0, br.y), bufferR)
        + dyeAt(cTex, uv - float2(0.0, br.y), bufferR)) / 6.0;
    float a = clamp(dye * 248.659 - 48.757, 0.0, 1.0);

    float loop = 2000.0 / 60.0;
    float time = u.bufferResolution.w;
    float lp = fract(time / loop);
    float fr = lp * 2000.0;
    float yf = 2.0 * R.y / R.x;
    float2 cen = float2(0.5, 0.5 * yf);
    float2 buv = float2(uv.x, uv.y * yf);
    float2 wsc = float2(warmBreathX(fr), warmBreathY(fr));
    float2 cb = (rot(coolWob(lp) * M_PI_F / 180.0) * (buv - cen) + cen) * 4.48 * coolBreath(fr);
    float2 wb = (rot(warmWob(lp) * M_PI_F / 180.0) * ((buv - cen) * wsc) + cen) * 3.5;
    float scrl = 1.0 / loop;
    float bb = bubbleTex(dTex, cb + float2(-scrl, -scrl) * time);
    float bo = bubbleTex(dTex, wb + float2(scrl, -scrl) * time);

    float3 warmTint[3] = { float3(0.113726, 0.0, 0.2), float3(0.003922, 0.027451, 0.0), float3(0.0, 0.019608, 0.086275) };
    float3 coolTint[3] = { float3(0.031373, -0.003922, -0.019608), float3(0.0, 0.05098, 0.003922), float3(0.121569, 0.0, -0.003922) };
    float3 warmC = mix(paletteWarm(from, u) + bo * warmTint[from], paletteWarm(to, u) + bo * warmTint[to], tt);
    float3 coolC = mix(paletteCool(from, u) + bb * coolTint[from], paletteCool(to, u) + bb * coolTint[to], tt);
    return float4(toSRGB(mix(coolC, warmC, a)), 1.0);
}

