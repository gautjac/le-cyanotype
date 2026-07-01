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
    // `toe` is the base-fog / veiling density (the darkest a print value can reach),
    // `shoulder` compresses the highlights. Returned value is print luminance
    // (1 = paper white, 0 = maximum deposited density).
    inline float hd_curve(float x, float gamma, float toe, float shoulder) {
        x = clamp(x, 0.0, 1.0);
        // Straight-line portion: gamma slope around mid grey.
        float g = pow(x, gamma);
        // Highlight shoulder: exponential roll-off so speculars turn creamy, not
        // clipped. Normalised so g == 1 stays at paper white.
        float k = 1.0 + shoulder * 2.0;
        float s = (1.0 - exp(-g * k)) / (1.0 - exp(-k));
        g = mix(g, s, shoulder);
        // Base fog: lift the floor so the deepest shadow carries a veiling density
        // `toe` (nothing on an aged print is truly paper-black), leaving white intact.
        g = toe + (1.0 - toe) * g;
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
    float3 spectral,               // per-channel actinic sensitivity (R,G,B weights)
    float  metalSheen,             // additive metallic specular in highlights (tintype/daguerreotype)
    float  silverGrain,            // how much visible silver grain the process carries
    float  bronzing)               // cyanotype Dmax bronze solarisation (1 = cyanotype, else 0)
{
    float3 base = src.rgb;

    // ── 1. Spectral / actinic response ──────────────────────────────────────
    // Old processes are not panchromatic. Each sees a characteristic slice of the
    // spectrum — cyanotype almost pure UV/blue (reds vanish, skies blow out),
    // collodion blue-sensitive, the daguerreotype the broadest of the five. We
    // collapse the scene to a single exposing "light value" through the process's
    // real per-channel sensitivity. Weights sum to ≈1, so a neutral grey keeps its
    // value and only coloured light is redistributed.
    float lightValue = dot(base, spectral);

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
    // Enrich the deposited pigment a touch so the Virage control reads as a real
    // dial — a neutral silver print at 0, the full process colour at 1 — rather than
    // a whisper of tint over grey.
    float tl = cy::luma(toned);
    toned = clamp(mix(float3(tl), toned, 1.18), 0.0, 1.0);
    // A neutral silver-grey reference to blend against when toning is dialed down.
    float3 neutralPrint = mix(float3(0.03), float3(0.97), 1.0 - dens);
    float3 col = mix(neutralPrint, toned, toning);

    // ── 4. Metal sheen (tintype/daguerreotype) ──────────────────────────────
    // The silver highlights of a plate process throw back a cool specular glint.
    // Add it only in the brightest, near-paper-white regions.
    float hi = smoothstep(0.72, 1.0, 1.0 - dens);
    col += metalSheen * hi * float3(0.55, 0.62, 0.70);

    // ── 5. Bronzing (cyanotype Dmax solarisation) ────────────────────────────
    // Where a cyanotype is exposed to its deepest density, the Prussian blue turns
    // over to a warm metallic bronze with a faint sheen — the classic "bronzed"
    // shadow. Only bites in the darkest deposit, and only for the cyanotype.
    float bronze = smoothstep(0.80, 1.0, dens) * bronzing;
    col = mix(col, col + float3(0.12, 0.06, -0.03), bronze);   // warm the deepest shadows
    col += bronze * 0.05 * float3(0.90, 0.72, 0.42);           // faint metallic glint

    // ── 6. Grain ─────────────────────────────────────────────────────────────
    // Silver grain is most visible in the mid densities, not the extremes, and
    // scales with how much silver the process deposits — the collodion plate grains
    // hardest. A floor keeps the control useful even on the near-grainless cyanotype,
    // where "grain" reads as paper-fibre / coating granularity.
    float g = grain.r - 0.5;
    float midWeight = 1.0 - abs((1.0 - dens) - 0.5) * 2.0; // peaks at mid grey
    float grainScale = 0.55 + 0.45 * silverGrain;
    col += g * grainAmount * grainScale * 0.70 * (0.45 + 0.55 * midWeight);

    col = clamp(col, 0.0, 1.0);
    return half4(half3(col), src.a);
}

} // extern "C"
