#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// Le Cyanotype — la chambre noire dans une pixel shader.
//
// A physically-motivated simulator of five 19th-century photographic processes.
// This is not a filter pack. Each process reproduces the real chemistry's
// behaviour: how the sensitized paper or plate *responds to light* (its
// characteristic H&D curve), what colour the developed image actually is (the
// pigment / metal it deposits), how much contrast it holds, and where it fails
// (fog, tarnish, uneven hand-coating, chemical speckle).
//
// The Swift side feeds the source colour, a paper/plate texture sample, a coated
// grain sample, and a pile of process constants. The kernel does the tone
// reproduction and the toning; the finishing imperfections (vignette, coating
// edge, real texture blends) are layered by the Core Image graph around it.
// ─────────────────────────────────────────────────────────────────────────────

namespace cy {

    // Rec. 709 luma — the "how much light hit this grain of silver salt" proxy.
    inline float luma(float3 c) {
        return dot(c, float3(0.2126, 0.7152, 0.0722));
    }

    // A soft filmic shoulder+toe. Real emulsions don't clip; density rolls off.
    // `gamma` sets the mid contrast (the slope of the straight-line portion),
    // `toe` lifts the shadows (base fog), `shoulder` compresses the highlights.
    inline float hd_curve(float x, float gamma, float toe, float shoulder) {
        x = clamp(x, 0.0, 1.0);
        // Straight-line portion via a gamma slope around mid grey.
        float g = pow(x, gamma);
        // Toe: lift the darkest values a touch (fog floor).
        g = mix(g, g * (0.75 + 0.25 * g) + toe, toe > 0.0 ? 0.6 : 0.0);
        g = max(g, toe);
        // Shoulder: compress highlights so speculars turn creamy, not clipped.
        float s = 1.0 - exp(-g * (1.0 + shoulder * 2.0));
        g = mix(g, s / (1.0 - exp(-(1.0 + shoulder * 2.0))), shoulder);
        return clamp(g, 0.0, 1.0);
    }

    // Duotone / split-tone map: paints a density value with a shadow colour and a
    // highlight colour, with a mid pivot so the transition sits where the process
    // actually places it. This is the "what pigment did the chemistry deposit".
    inline float3 tone_map(float density, float3 shadowC, float3 midC, float3 highC, float pivot) {
        // density: 0 = paper white (no exposure), 1 = full deposit (shadow).
        // Invert so 1 = highlight/paper, 0 = deepest shadow, for intuitive lerp.
        float v = 1.0 - density;
        float lo = smoothstep(0.0, pivot, v);
        float hi = smoothstep(pivot, 1.0, v);
        float3 shadowToMid = mix(shadowC, midC, lo);
        float3 midToHigh   = mix(midC, highC, hi);
        return mix(shadowToMid, midToHigh, step(pivot, v));
    }
}

extern "C" {

// ─────────────────────────────────────────────────────────────────────────────
// The master process kernel. `process` selects the chemistry:
//   0 cyanotype · 1 tintype (ferrotype) · 2 daguerreotype · 3 Van Dyke brown · 4 salt/albumen
//
// Arguments after the samples are the user controls plus per-process constants
// the Swift layer looks up from a physically-tuned table.
// ─────────────────────────────────────────────────────────────────────────────
[[ stitchable ]] half4 altProcess(
    coreimage::sample_t src,       // linear-ish source colour
    coreimage::sample_t grain,     // 1-channel coated grain noise (0..1)
    float  process,
    float  exposure,               // EV, stops
    float  contrast,               // multiplier on the mid slope
    float  toning,                 // 0..1 strength of the process colour vs neutral
    float  grainAmount,            // 0..1 chemical / silver grain
    // characteristic-curve constants
    float  gamma, float toe, float shoulder,
    // tone colours (shadow, mid, highlight) and pivot
    float3 shadowC, float3 midC, float3 highC, float pivot,
    // process quirks
    float  desatBias,              // how monochromatic the process is (UV/collodion response)
    float  metalSheen)             // additive metallic specular in highlights (tintype/daguerreotype)
{
    float3 base = src.rgb;

    // ── 1. Spectral / actinic response ──────────────────────────────────────
    // Old processes are not panchromatic. Cyanotype & salt respond mostly to UV/
    // blue, so reds & greens go dark and skies blow out; collodion (tintype) is
    // blue-sensitive too, rendering warm skin dark and skies pale. We model this
    // by weighting the channels toward the process's real spectral sensitivity
    // before collapsing to a single density, then blend toward plain luma by
    // desatBias so fully-neutral processes still read naturally.
    float uvResponse = dot(base, float3(0.10, 0.30, 0.60)); // blue-weighted
    float neutral    = cy::luma(base);
    float lightValue = mix(uvResponse, neutral, desatBias);

    // Exposure in stops, applied in the light domain (before the paper curve).
    lightValue *= exp2(exposure);
    lightValue = clamp(lightValue, 0.0, 1.0);

    // ── 2. Characteristic (H&D) curve ───────────────────────────────────────
    // Map scene light → deposited density through the emulsion's real response,
    // then apply the user contrast around the mid.
    float dens = 1.0 - cy::hd_curve(lightValue, gamma, toe, shoulder);
    dens = clamp((dens - 0.5) * contrast + 0.5, 0.0, 1.0);

    // ── 3. Toning: paint the density with the process's pigment/metal ────────
    float3 toned = cy::tone_map(dens, shadowC, midC, highC, pivot);
    // A neutral silver-grey reference to blend against when toning is dialed down.
    float3 neutralPrint = mix(float3(0.03), float3(0.97), 1.0 - dens);
    float3 col = mix(neutralPrint, toned, toning);

    // ── 4. Metal sheen (tintype/daguerreotype) ──────────────────────────────
    // The silver highlights of a plate process throw back a cool specular glint.
    // Add it only in the brightest, near-paper-white regions.
    float hi = smoothstep(0.72, 1.0, 1.0 - dens);
    col += metalSheen * hi * float3(0.55, 0.62, 0.70);

    // ── 5. Grain ─────────────────────────────────────────────────────────────
    // Silver / chemical grain is most visible in the mid densities, not the
    // extremes. Modulate the incoming grain sample by a mid-tone weight.
    float g = grain.r - 0.5;
    float midWeight = 1.0 - abs((1.0 - dens) - 0.5) * 2.0; // peaks at mid grey
    col += g * grainAmount * 0.28 * (0.4 + 0.6 * midWeight);

    col = clamp(col, 0.0, 1.0);
    return half4(half3(col), src.a);
}

} // extern "C"
