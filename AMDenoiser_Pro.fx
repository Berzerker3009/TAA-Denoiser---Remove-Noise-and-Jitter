/**
 * ============================================================
 *  AMDenoiser Pro  v5.0
 *  Depth-Zoned Denoiser | 8 Filter Types | Full Stabilization
 * ============================================================
 *
 *  NEW in v5 — 3 extra filters for distant shaky noise:
 *
 *   5 · Kuwahara             Structure-preserving strong smoother.
 *                            Divides neighbourhood into 4 quadrants,
 *                            picks the quadrant with least variance.
 *                            Eliminates noise while keeping hard edges.
 *                            Best for: foliage, terrain, sky shimmer.
 *
 *   6 · Bilateral-Temporal   Cross-frame bilateral — weights neighbours
 *                            by BOTH spatial colour AND history agreement.
 *                            Pixels that were stable last frame get more
 *                            weight, noisy/jittery ones get less.
 *                            Best for: persistent distant jitter,
 *                            grass/tree canopy shimmer.
 *
 *   7 · SVGF-Lite            Spatially-Varying Gaussian Filter weighted
 *                            by depth similarity. Ignores pixels at
 *                            different depth (depth discontinuities) to
 *                            prevent smearing across depth layers.
 *                            Adds a luma-history feedback term that
 *                            exponentially damps oscillating pixels.
 *                            Best for: horizon line noise, cliff edges,
 *                            distant rooftop shimmer, shaky silhouettes.
 *
 * ============================================================
 */

#include "ReShade.fxh"

// ─────────────────────────────────────────────────────────────
//  CATEGORY LABELS
// ─────────────────────────────────────────────────────────────
#define CAT_GLOBAL  "[ 1 · Global & Filter Type ]"
#define CAT_DEPTH   "[ 2 · Depth Zone Thresholds ]"
#define CAT_NEAR    "[ 3 · Near Zone  (close objects) ]"
#define CAT_MID     "[ 4 · Mid Zone   (medium distance) ]"
#define CAT_FAR     "[ 5 · Far Zone   (distant / background) ]"
#define CAT_SHARP   "[ 6 · Sharpness Recovery ]"
#define CAT_STAB    "[ 7 · Stabilization & Anti-Jitter ]"
#define CAT_DEBUG   "[ 8 · Debug ]"

// ─────────────────────────────────────────────────────────────
//  1 · GLOBAL & FILTER TYPE
// ─────────────────────────────────────────────────────────────

uniform bool EnableDenoiser <
    ui_category = CAT_GLOBAL;
    ui_label    = "Enable AMDenoiser Pro";
    ui_tooltip  = "Master on/off switch.";
> = true;

uniform int FilterType <
    ui_category = CAT_GLOBAL;
    ui_type     = "combo";
    ui_label    = "Filter Type";
    ui_tooltip  =
        "──── Standard Filters ────────────────────────────────────\n"
        "0 · Bilateral         Edge-aware weighted average.\n"
        "                      Best general-purpose. Preserves edges.\n\n"
        "1 · Gaussian          Distance-weighted blur. Soft and uniform.\n"
        "                      Good for heavy grain. Slight edge blur.\n\n"
        "2 · Mean              Simple box average. Fastest.\n"
        "                      Useful for uniform noise, blurs edges.\n\n"
        "3 · NLM-Lite          Non-Local Means patch similarity.\n"
        "                      Best quality. Higher GPU cost.\n\n"
        "4 · Median-Approx     Removes extreme outliers / fireflies.\n"
        "                      Great for TAA sparks, specular glitter.\n\n"
        "──── Strong Distant Noise Filters ────────────────────────\n"
        "5 · Kuwahara          Structure-preserving strong smoother.\n"
        "                      Picks the least-variance quadrant.\n"
        "                      Kills distant shimmer, keeps hard edges.\n"
        "                      BEST FOR: foliage, terrain, sky noise.\n\n"
        "6 · Bilateral-Temporal  Cross-frame bilateral filter.\n"
        "                      Weights samples by colour AND history.\n"
        "                      Stable pixels get boosted, jittery get cut.\n"
        "                      BEST FOR: persistent grass/tree shimmer.\n\n"
        "7 · SVGF-Lite         Depth-aware Spatially-Varying Gaussian.\n"
        "                      Rejects samples at different depth layers.\n"
        "                      Adds exponential luma-history damping.\n"
        "                      BEST FOR: horizon lines, cliff edges,\n"
        "                      distant silhouette shake, rooftop noise.";
    ui_items    =
        "0 · Bilateral (edge-preserving)\0"
        "1 · Gaussian  (soft uniform blur)\0"
        "2 · Mean      (box average, fastest)\0"
        "3 · NLM-Lite  (patch similarity, best quality)\0"
        "4 · Median-Approx (firefly / spark removal)\0"
        "5 · Kuwahara  (strong structure-preserving, foliage/sky)\0"
        "6 · Bilateral-Temporal (cross-frame, persistent shimmer)\0"
        "7 · SVGF-Lite (depth-aware, horizon/edge shake)\0";
> = 0;

uniform float GlobalMix <
    ui_category = CAT_GLOBAL;
    ui_type     = "slider";
    ui_label    = "Global Mix";
    ui_tooltip  = "0 = original image only.  1 = fully processed.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 1.0;

uniform int SampleQuality <
    ui_category = CAT_GLOBAL;
    ui_type     = "combo";
    ui_label    = "Sample Quality";
    ui_tooltip  = "Neighbour sample count per zone.\nFast=4  Balanced=8  High=12  Ultra=16";
    ui_items    = "Fast (4)\0Balanced (8)\0High (12)\0Ultra (16)\0";
> = 1;

// ─────────────────────────────────────────────────────────────
//  NEW FILTER PARAMETERS
// ─────────────────────────────────────────────────────────────

uniform float KuwaharaRadius <
    ui_category = CAT_GLOBAL;
    ui_type     = "slider";
    ui_label    = "Kuwahara Radius (px)  [Filter 5]";
    ui_tooltip  = "Size of each Kuwahara quadrant in pixels.\n"
                  "Larger = stronger smoothing. 2-4 works well at 4K.\n"
                  "Does not blur edges — picks the quietest region.";
    ui_min = 1.0; ui_max = 6.0; ui_step = 0.5;
> = 2.0;

uniform float BilateralTemporalWeight <
    ui_category = CAT_GLOBAL;
    ui_type     = "slider";
    ui_label    = "Bilateral-Temporal History Weight  [Filter 6]";
    ui_tooltip  = "How much the previous frame's values influence the filter.\n"
                  "Higher = stable pixels are trusted more, jittery ones suppressed harder.\n"
                  "0 = acts like plain Bilateral.  1 = history dominates.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.55;

uniform float SVGFDepthSensitivity <
    ui_category = CAT_GLOBAL;
    ui_type     = "slider";
    ui_label    = "SVGF Depth Sensitivity  [Filter 7]";
    ui_tooltip  = "How strictly SVGF rejects samples at different depths.\n"
                  "Higher = tighter depth matching, less cross-layer bleed.\n"
                  "Lower = softer, blends more across depth boundaries.";
    ui_min = 1.0; ui_max = 50.0; ui_step = 0.5;
> = 15.0;

uniform float SVGFHistoryDamp <
    ui_category = CAT_GLOBAL;
    ui_type     = "slider";
    ui_label    = "SVGF History Damping  [Filter 7]";
    ui_tooltip  = "Exponential decay applied to pixels that oscillate between frames.\n"
                  "Higher = more aggressive luma-history smoothing.\n"
                  "Directly eliminates distant shaky noise.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.65;

// ─────────────────────────────────────────────────────────────
//  2 · DEPTH ZONE THRESHOLDS
// ─────────────────────────────────────────────────────────────

uniform float NearFarEdge <
    ui_category = CAT_DEPTH;
    ui_type     = "slider";
    ui_label    = "Near to Mid Boundary";
    ui_tooltip  = "Linear depth where Near zone ends and Mid begins.\nUse Debug > Zone Overlay to visualise.";
    ui_min = 0.0; ui_max = 0.5; ui_step = 0.005;
> = 0.08;

uniform float MidFarEdge <
    ui_category = CAT_DEPTH;
    ui_type     = "slider";
    ui_label    = "Mid to Far Boundary";
    ui_tooltip  = "Linear depth where Mid zone ends and Far begins.";
    ui_min = 0.1; ui_max = 1.0; ui_step = 0.005;
> = 0.35;

uniform float ZoneBlend <
    ui_category = CAT_DEPTH;
    ui_type     = "slider";
    ui_label    = "Zone Blend Width";
    ui_tooltip  = "Smooth crossfade width between adjacent zones.";
    ui_min = 0.0; ui_max = 0.15; ui_step = 0.005;
> = 0.04;

// ─────────────────────────────────────────────────────────────
//  3 · NEAR ZONE
// ─────────────────────────────────────────────────────────────

uniform float NearStrength <
    ui_category = CAT_NEAR;
    ui_type     = "slider";
    ui_label    = "Near Denoise Strength";
    ui_tooltip  = "Overall denoising blend for close objects.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.25;

uniform float NearRadius <
    ui_category = CAT_NEAR;
    ui_type     = "slider";
    ui_label    = "Near Radius (px)";
    ui_min = 0.5; ui_max = 4.0; ui_step = 0.1;
> = 1.0;

uniform float NearLuma <
    ui_category = CAT_NEAR;
    ui_type     = "slider";
    ui_label    = "Near Luma Edge Sensitivity";
    ui_tooltip  = "Higher = brightness edges preserved more sharply.";
    ui_min = 0.1; ui_max = 8.0; ui_step = 0.1;
> = 3.5;

uniform float NearChroma <
    ui_category = CAT_NEAR;
    ui_type     = "slider";
    ui_label    = "Near Chroma Edge Sensitivity";
    ui_tooltip  = "Higher = colour edges preserved more sharply.";
    ui_min = 0.1; ui_max = 8.0; ui_step = 0.1;
> = 2.0;

uniform float NearFastNoise <
    ui_category = CAT_NEAR;
    ui_type     = "slider";
    ui_label    = "Near Fast Noise Reduction";
    ui_tooltip  = "Blends high-variance pixels toward their local average.\nTargets random grain without blurring edges.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.20;

uniform float NearJitter <
    ui_category = CAT_NEAR;
    ui_type     = "slider";
    ui_label    = "Near Jitter Suppression";
    ui_tooltip  = "Additional temporal blend weight for Near zone.";
    ui_min = 0.0; ui_max = 0.6; ui_step = 0.01;
> = 0.10;

uniform float NearNoiseStab <
    ui_category = CAT_NEAR;
    ui_type     = "slider";
    ui_label    = "Near Noise Stabilizer";
    ui_tooltip  = "Variance-based temporal damping for Near zone.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.15;

// ─────────────────────────────────────────────────────────────
//  4 · MID ZONE
// ─────────────────────────────────────────────────────────────

uniform float MidStrength <
    ui_category = CAT_MID;
    ui_type     = "slider";
    ui_label    = "Mid Denoise Strength";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.55;

uniform float MidRadius <
    ui_category = CAT_MID;
    ui_type     = "slider";
    ui_label    = "Mid Radius (px)";
    ui_min = 0.5; ui_max = 6.0; ui_step = 0.1;
> = 2.0;

uniform float MidLuma <
    ui_category = CAT_MID;
    ui_type     = "slider";
    ui_label    = "Mid Luma Edge Sensitivity";
    ui_min = 0.1; ui_max = 8.0; ui_step = 0.1;
> = 2.5;

uniform float MidChroma <
    ui_category = CAT_MID;
    ui_type     = "slider";
    ui_label    = "Mid Chroma Edge Sensitivity";
    ui_min = 0.1; ui_max = 8.0; ui_step = 0.1;
> = 1.5;

uniform float MidFastNoise <
    ui_category = CAT_MID;
    ui_type     = "slider";
    ui_label    = "Mid Fast Noise Reduction";
    ui_tooltip  = "Crushes high-frequency random grain at medium distances.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.35;

uniform float MidJitter <
    ui_category = CAT_MID;
    ui_type     = "slider";
    ui_label    = "Mid Jitter Suppression";
    ui_min = 0.0; ui_max = 0.6; ui_step = 0.01;
> = 0.18;

uniform float MidNoiseStab <
    ui_category = CAT_MID;
    ui_type     = "slider";
    ui_label    = "Mid Noise Stabilizer";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.25;

// ─────────────────────────────────────────────────────────────
//  5 · FAR ZONE
// ─────────────────────────────────────────────────────────────

uniform float FarStrength <
    ui_category = CAT_FAR;
    ui_type     = "slider";
    ui_label    = "Far Denoise Strength";
    ui_tooltip  = "Distant backgrounds, foliage, sky. Can be pushed high.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.85;

uniform float FarRadius <
    ui_category = CAT_FAR;
    ui_type     = "slider";
    ui_label    = "Far Radius (px)";
    ui_tooltip  = "Larger = smoother distant areas. 3-5 recommended at 4K.";
    ui_min = 0.5; ui_max = 8.0; ui_step = 0.1;
> = 3.5;

uniform float FarLuma <
    ui_category = CAT_FAR;
    ui_type     = "slider";
    ui_label    = "Far Luma Edge Sensitivity";
    ui_min = 0.1; ui_max = 8.0; ui_step = 0.1;
> = 1.5;

uniform float FarChroma <
    ui_category = CAT_FAR;
    ui_type     = "slider";
    ui_label    = "Far Chroma Edge Sensitivity";
    ui_min = 0.1; ui_max = 8.0; ui_step = 0.1;
> = 1.0;

uniform float FarFastNoise <
    ui_category = CAT_FAR;
    ui_type     = "slider";
    ui_label    = "Far Fast Noise Reduction";
    ui_tooltip  = "Aggressively crushes grain in distant areas.\nVery effective on foliage, grass, skyboxes.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.65;

uniform float FarJitter <
    ui_category = CAT_FAR;
    ui_type     = "slider";
    ui_label    = "Far Jitter Suppression";
    ui_tooltip  = "Extra temporal blend for distant shimmer.\nMost effective against foliage flicker and grass noise.";
    ui_min = 0.0; ui_max = 0.8; ui_step = 0.01;
> = 0.35;

uniform float FarNoiseStab <
    ui_category = CAT_FAR;
    ui_type     = "slider";
    ui_label    = "Far Noise Stabilizer";
    ui_tooltip  = "Variance-clamped temporal damping in Far zone.\nLocks down flickering pixels in distant foliage/clouds/water.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.50;

// ─────────────────────────────────────────────────────────────
//  6 · SHARPNESS RECOVERY
// ─────────────────────────────────────────────────────────────

uniform bool EnableSharpness <
    ui_category = CAT_SHARP;
    ui_label    = "Enable Sharpness Recovery";
    ui_tooltip  = "Unsharp-mask pass after denoising to recover fine edge detail.";
> = true;

uniform float SharpStrength <
    ui_category = CAT_SHARP;
    ui_type     = "slider";
    ui_label    = "Sharpness Strength";
    ui_min = 0.0; ui_max = 1.5; ui_step = 0.01;
> = 0.45;

uniform float SharpClamp <
    ui_category = CAT_SHARP;
    ui_type     = "slider";
    ui_label    = "Sharpness Clamp (halo limiter)";
    ui_min = 0.0; ui_max = 0.3; ui_step = 0.005;
> = 0.045;

uniform float SharpNearScale <
    ui_category = CAT_SHARP;
    ui_type     = "slider";
    ui_label    = "Sharpness Scale Near";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 1.2;

uniform float SharpFarScale <
    ui_category = CAT_SHARP;
    ui_type     = "slider";
    ui_label    = "Sharpness Scale Far";
    ui_tooltip  = "Keep low — sharpening Far zone re-introduces noise.";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 0.4;

// ─────────────────────────────────────────────────────────────
//  7 · STABILIZATION & ANTI-JITTER
// ─────────────────────────────────────────────────────────────

uniform bool EnableTemporal <
    ui_category = CAT_STAB;
    ui_label    = "Enable Temporal Stabilization";
    ui_tooltip  = "Master toggle for all temporal features.";
> = true;

uniform float TemporalBlend <
    ui_category = CAT_STAB;
    ui_type     = "slider";
    ui_label    = "Global Temporal Blend";
    ui_tooltip  = "Base history blend. Per-zone Jitter adds on top.\nHigher = more stable. Risk: ghosting on fast motion.";
    ui_min = 0.0; ui_max = 0.6; ui_step = 0.01;
> = 0.12;

uniform float MotionRejectThreshold <
    ui_category = CAT_STAB;
    ui_type     = "slider";
    ui_label    = "Motion Rejection Threshold";
    ui_tooltip  = "Reduces temporal blend when a pixel changes brightness quickly.\nLower = less ghosting. Higher = more jitter suppression.";
    ui_min = 0.01; ui_max = 0.5; ui_step = 0.005;
> = 0.08;

uniform float MotionRejectStrength <
    ui_category = CAT_STAB;
    ui_type     = "slider";
    ui_label    = "Motion Rejection Strength";
    ui_tooltip  = "How much to reduce blend on motion.\n0 = never reduce. 1 = fully cut on motion.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.75;

uniform float MicroJitterDamp <
    ui_category = CAT_STAB;
    ui_type     = "slider";
    ui_label    = "Micro-Jitter Damping";
    ui_tooltip  = "Targets sub-pixel shimmer on fine detail: hair, wire, grilles.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.25;

uniform float FlickerDamp <
    ui_category = CAT_STAB;
    ui_type     = "slider";
    ui_label    = "Flicker Damping";
    ui_tooltip  = "Damps luminance oscillation between frames.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.30;

uniform float FlickerThreshold <
    ui_category = CAT_STAB;
    ui_type     = "slider";
    ui_label    = "Flicker Detection Threshold";
    ui_min = 0.005; ui_max = 0.25; ui_step = 0.005;
> = 0.04;

uniform float ShakeDamp <
    ui_category = CAT_STAB;
    ui_type     = "slider";
    ui_label    = "Shake Stabilizer";
    ui_tooltip  = "Suppresses low-frequency frame instability / camera shake.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.20;

uniform float NoiseFloorClamp <
    ui_category = CAT_STAB;
    ui_type     = "slider";
    ui_label    = "Noise Floor Clamp";
    ui_tooltip  = "Minimum variance before stabilizer engages.\nRaise if image looks too plastic after stabilization.";
    ui_min = 0.0; ui_max = 0.1; ui_step = 0.001;
> = 0.012;

uniform float StabilizeSpeed <
    ui_category = CAT_STAB;
    ui_type     = "slider";
    ui_label    = "Stabilization Response Speed";
    ui_tooltip  = "Scales all temporal blend weights.\nLow = slow/stable. High = fast/less ghosting.";
    ui_min = 0.05; ui_max = 1.0; ui_step = 0.01;
> = 0.35;

// ─────────────────────────────────────────────────────────────
//  8 · DEBUG
// ─────────────────────────────────────────────────────────────

uniform int DebugMode <
    ui_category = CAT_DEBUG;
    ui_type     = "combo";
    ui_label    = "Debug View";
    ui_items    =
        "Off\0"
        "Depth Map\0"
        "Zone Overlay  R=Near  G=Mid  B=Far\0"
        "Denoised Only (no sharpen/temporal)\0"
        "Temporal Weight Map\0"
        "Fast Noise Variance Map\0";
> = 0;

// ─────────────────────────────────────────────────────────────
//  TEXTURES & SAMPLERS
// ─────────────────────────────────────────────────────────────

texture texStabilized  { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sampStabilized { Texture = texStabilized; AddressU = CLAMP; AddressV = CLAMP; };

texture texPrevLuma    { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sampPrevLuma   { Texture = texPrevLuma;  AddressU = CLAMP; AddressV = CLAMP; };

// ─────────────────────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────────────────────

float  Luma(float3 c)      { return dot(c, float3(0.299, 0.587, 0.114)); }
float3 ReadSample(float2 p){ return tex2Dlod(ReShade::BackBuffer, float4(p, 0, 0)).rgb; }

float3 ZoneWeights(float depth)
{
    float hw    = ZoneBlend * 0.5;
    float wNear = 1.0 - smoothstep(NearFarEdge - hw, NearFarEdge + hw, depth);
    float wFar  = smoothstep(MidFarEdge - hw, MidFarEdge + hw, depth);
    float wMid  = saturate(1.0 - wNear - wFar);
    return float3(wNear, wMid, wFar);
}

// ─────────────────────────────────────────────────────────────
//  NLM PATCH WEIGHT  (2×2 patch comparison)
// ─────────────────────────────────────────────────────────────

float NLMWeight(float2 sUV, float2 uv, float h2)
{
    float2 px = ReShade::PixelSize;
    float3 p0 = ReadSample(uv  + float2(-px.x,-px.y));
    float3 p1 = ReadSample(uv  + float2( px.x,-px.y));
    float3 p2 = ReadSample(uv  + float2(-px.x, px.y));
    float3 p3 = ReadSample(uv  + float2( px.x, px.y));
    float3 q0 = ReadSample(sUV + float2(-px.x,-px.y));
    float3 q1 = ReadSample(sUV + float2( px.x,-px.y));
    float3 q2 = ReadSample(sUV + float2(-px.x, px.y));
    float3 q3 = ReadSample(sUV + float2( px.x, px.y));
    float d = dot(p0-q0,p0-q0)+dot(p1-q1,p1-q1)+dot(p2-q2,p2-q2)+dot(p3-q3,p3-q3);
    return exp(-max(d - 0.0002, 0.0) / h2);
}

// ─────────────────────────────────────────────────────────────
//  KUWAHARA — one quadrant's mean + variance
// ─────────────────────────────────────────────────────────────

void KuwaharaQuadrant(float2 uv, float2 o1, float2 o2, float2 o3, float2 o4,
                      out float3 meanOut, out float varOut)
{
    float3 s0 = ReadSample(uv + o1);
    float3 s1 = ReadSample(uv + o2);
    float3 s2 = ReadSample(uv + o3);
    float3 s3 = ReadSample(uv + o4);
    float3 center = tex2D(ReShade::BackBuffer, uv).rgb;
    meanOut = (center + s0 + s1 + s2 + s3) * 0.2;
    // Variance measured in luma
    float l0 = Luma(s0); float l1 = Luma(s1);
    float l2 = Luma(s2); float l3 = Luma(s3);
    float lc = Luma(center);
    float avg = (lc + l0 + l1 + l2 + l3) * 0.2;
    varOut = ((lc-avg)*(lc-avg) + (l0-avg)*(l0-avg) + (l1-avg)*(l1-avg)
            + (l2-avg)*(l2-avg) + (l3-avg)*(l3-avg)) * 0.2;
}

// ─────────────────────────────────────────────────────────────
//  KUWAHARA FILTER
//  4 quadrants: TL, TR, BL, BR.  Pick the one with lowest variance.
//  Keeps hard edges while aggressively smoothing flat/noisy areas.
// ─────────────────────────────────────────────────────────────

float3 FilterKuwahara(float2 uv, float radius)
{
    float2 px = ReShade::PixelSize * radius;
    float2 hx = float2(px.x, 0.0);
    float2 hy = float2(0.0,  px.y);
    float2 d  = px * 0.7071;

    float3 m0, m1, m2, m3;
    float  v0, v1, v2, v3;

    // Top-Left quadrant
    KuwaharaQuadrant(uv, -hx, -hy, -d, float2(0,0), m0, v0);
    // Top-Right quadrant
    KuwaharaQuadrant(uv,  hx, -hy,  float2( d.x,-d.y), float2(0,0), m1, v1);
    // Bottom-Left quadrant
    KuwaharaQuadrant(uv, -hx,  hy,  float2(-d.x, d.y), float2(0,0), m2, v2);
    // Bottom-Right quadrant
    KuwaharaQuadrant(uv,  hx,  hy,  d, float2(0,0), m3, v3);

    // Pick quadrant with minimum variance
    float3 result = m0; float vMin = v0;
    if (v1 < vMin) { result = m1; vMin = v1; }
    if (v2 < vMin) { result = m2; vMin = v2; }
    if (v3 < vMin) { result = m3; }
    return result;
}

// ─────────────────────────────────────────────────────────────
//  BILATERAL-TEMPORAL FILTER
//  Standard bilateral weight × history agreement weight.
//  Samples that agree with previous frame are trusted more.
//  Jittery samples that disagree with history are penalised.
// ─────────────────────────────────────────────────────────────

float3 FilterBilateralTemporal(float2 uv, float radius, float lumaW, float chromaW,
                                float histWeight)
{
    float3 center  = tex2D(ReShade::BackBuffer, uv).rgb;
    float  cLuma   = Luma(center);
    float3 prevC   = tex2D(sampStabilized, uv).rgb;
    float  prevL   = Luma(prevC);

    float2 px  = ReShade::PixelSize * radius;
    float  sq  = 0.7071;
    float2 d1  = px * sq;
    float2 px2 = px * 2.0;
    float2 d2  = px2 * sq;

    float2 A0=uv+float2( px.x, 0.0 ), A1=uv+float2(-px.x, 0.0 );
    float2 A2=uv+float2( 0.0,  px.y), A3=uv+float2( 0.0, -px.y);
    float2 B0=uv+float2( d1.x, d1.y), B1=uv+float2(-d1.x, d1.y);
    float2 B2=uv+float2( d1.x,-d1.y), B3=uv+float2(-d1.x,-d1.y);
    float2 C0=uv+float2( px2.x, 0.0 ),C1=uv+float2(-px2.x, 0.0 );
    float2 C2=uv+float2( 0.0, px2.y ), C3=uv+float2( 0.0,-px2.y);
    float2 D0=uv+float2( d2.x, d2.y), D1=uv+float2(-d2.x, d2.y);
    float2 D2=uv+float2( d2.x,-d2.y), D3=uv+float2(-d2.x,-d2.y);

    float3 sumC = center;
    float  sumW = 1.0;

    #define BT_SAMPLE(POS) {                                                        \
        float3 col  = ReadSample(POS);                                              \
        float3 prev = tex2Dlod(sampStabilized, float4(POS, 0, 0)).rgb;             \
        float  ld   = abs(Luma(col) - cLuma) * lumaW;                              \
        float  cd   = length(col - center)   * chromaW;                            \
        float  hd   = length(col - prev)     * histWeight * 4.0;                   \
        float  w    = exp(-(ld + cd + hd));                                         \
        sumC += col * w; sumW += w;                                                 \
    }

    BT_SAMPLE(A0) BT_SAMPLE(A1) BT_SAMPLE(A2) BT_SAMPLE(A3)
    if (SampleQuality >= 1) { BT_SAMPLE(B0) BT_SAMPLE(B1) BT_SAMPLE(B2) BT_SAMPLE(B3) }
    if (SampleQuality >= 2) { BT_SAMPLE(C0) BT_SAMPLE(C1) BT_SAMPLE(C2) BT_SAMPLE(C3) }
    if (SampleQuality >= 3) { BT_SAMPLE(D0) BT_SAMPLE(D1) BT_SAMPLE(D2) BT_SAMPLE(D3) }
    #undef BT_SAMPLE

    return sumC / sumW;
}

// ─────────────────────────────────────────────────────────────
//  SVGF-LITE — Spatially-Varying Gaussian with Depth Rejection
//              + Luma History Exponential Damping
//
//  Weights each neighbour by:
//    · Gaussian spatial falloff
//    · Depth similarity (rejects cross-depth samples)
//    · Luma history agreement (damps oscillating pixels)
//
//  The history damping term is the key innovation:
//  pixels that were different last frame get penalised,
//  so only stable pixels contribute to the average.
//  This directly kills distant shaky noise even in 1 pass.
// ─────────────────────────────────────────────────────────────

float3 FilterSVGF(float2 uv, float radius, float depthSens, float histDamp)
{
    float3 center    = tex2D(ReShade::BackBuffer, uv).rgb;
    float  cDepth    = ReShade::GetLinearizedDepth(uv);
    float  cLumaPrev = tex2D(sampPrevLuma, uv).r;
    float  cLuma     = Luma(center);
    // Luma oscillation factor — how much this pixel itself is shaking
    float  selfOsc   = abs(cLuma - cLumaPrev);

    float2 px  = ReShade::PixelSize * radius;
    float  sq  = 0.7071;
    float2 d1  = px * sq;
    float2 px2 = px * 2.0;
    float2 d2  = px2 * sq;
    float  sigma = radius * 1.2;

    float2 A0=uv+float2( px.x, 0.0 ), A1=uv+float2(-px.x, 0.0 );
    float2 A2=uv+float2( 0.0,  px.y), A3=uv+float2( 0.0, -px.y);
    float2 B0=uv+float2( d1.x, d1.y), B1=uv+float2(-d1.x, d1.y);
    float2 B2=uv+float2( d1.x,-d1.y), B3=uv+float2(-d1.x,-d1.y);
    float2 C0=uv+float2( px2.x, 0.0 ),C1=uv+float2(-px2.x, 0.0 );
    float2 C2=uv+float2( 0.0, px2.y ), C3=uv+float2( 0.0,-px2.y);
    float2 D0=uv+float2( d2.x, d2.y), D1=uv+float2(-d2.x, d2.y);
    float2 D2=uv+float2( d2.x,-d2.y), D3=uv+float2(-d2.x,-d2.y);

    // Center weight starts at 1, but reduce it if center pixel itself is shaking
    float  cOscPenalty = saturate(selfOsc * histDamp * 8.0);
    float3 sumC = center * (1.0 - cOscPenalty * 0.5);
    float  sumW = (1.0 - cOscPenalty * 0.5);

    #define SVGF_SAMPLE(POS) {                                                         \
        float3 col   = ReadSample(POS);                                                \
        float  sD    = ReShade::GetLinearizedDepth(POS);                               \
        float  sLP   = tex2Dlod(sampPrevLuma, float4(POS, 0, 0)).r;                   \
        float  sLc   = Luma(col);                                                      \
        /* Gaussian spatial */                                                          \
        float2 off   = (POS - uv) / ReShade::PixelSize;                               \
        float  wGauss = exp(-dot(off,off) / (2.0*sigma*sigma));                       \
        /* Depth similarity — reject cross-layer samples */                             \
        float  depthDiff = abs(sD - cDepth) * depthSens;                              \
        float  wDepth    = exp(-depthDiff * depthDiff);                               \
        /* Luma history agreement — penalise oscillating samples */                     \
        float  oscAmt    = abs(sLc - sLP);                                             \
        float  wHist     = exp(-oscAmt * histDamp * 12.0);                            \
        float  w = wGauss * wDepth * wHist;                                           \
        sumC += col * w; sumW += w;                                                    \
    }

    SVGF_SAMPLE(A0) SVGF_SAMPLE(A1) SVGF_SAMPLE(A2) SVGF_SAMPLE(A3)
    if (SampleQuality >= 1) { SVGF_SAMPLE(B0) SVGF_SAMPLE(B1) SVGF_SAMPLE(B2) SVGF_SAMPLE(B3) }
    if (SampleQuality >= 2) { SVGF_SAMPLE(C0) SVGF_SAMPLE(C1) SVGF_SAMPLE(C2) SVGF_SAMPLE(C3) }
    if (SampleQuality >= 3) { SVGF_SAMPLE(D0) SVGF_SAMPLE(D1) SVGF_SAMPLE(D2) SVGF_SAMPLE(D3) }
    #undef SVGF_SAMPLE

    return sumC / max(sumW, 0.001);
}

// ─────────────────────────────────────────────────────────────
//  UNIFIED DENOISE  — dispatches to all 8 filter types
// ─────────────────────────────────────────────────────────────

float3 Denoise(float2 uv, float radius, float lumaW, float chromaW)
{
    float3 center = tex2D(ReShade::BackBuffer, uv).rgb;
    float  cLuma  = Luma(center);

    // ── New filters route directly — no shared position block needed ──
    if (FilterType == 5)
        return FilterKuwahara(uv, KuwaharaRadius);

    if (FilterType == 6)
        return FilterBilateralTemporal(uv, radius, lumaW, chromaW, BilateralTemporalWeight);

    if (FilterType == 7)
        return FilterSVGF(uv, radius, SVGFDepthSensitivity, SVGFHistoryDamp);

    // ── Standard filters — shared 16-position block ───────────
    float2 px  = ReShade::PixelSize * radius;
    float  sq  = 0.7071;
    float2 d1  = px * sq;
    float2 px2 = px * 2.0;
    float2 d2  = px2 * sq;
    float  sigma = radius * 1.5;
    float  h2    = max(1.0 / (chromaW * chromaW * 80.0), 0.0001);

    float2 A0=uv+float2( px.x, 0.0 ), A1=uv+float2(-px.x, 0.0 );
    float2 A2=uv+float2( 0.0,  px.y), A3=uv+float2( 0.0, -px.y);
    float2 B0=uv+float2( d1.x, d1.y), B1=uv+float2(-d1.x, d1.y);
    float2 B2=uv+float2( d1.x,-d1.y), B3=uv+float2(-d1.x,-d1.y);
    float2 C0=uv+float2( px2.x, 0.0 ),C1=uv+float2(-px2.x, 0.0 );
    float2 C2=uv+float2( 0.0, px2.y ), C3=uv+float2( 0.0,-px2.y);
    float2 D0=uv+float2( d2.x, d2.y), D1=uv+float2(-d2.x, d2.y);
    float2 D2=uv+float2( d2.x,-d2.y), D3=uv+float2(-d2.x,-d2.y);

    float3 sumC = center;
    float  sumW = 1.0;

    // ── BILATERAL ─────────────────────────────────────────────
    if (FilterType == 0)
    {
        float w; float3 col;
        #define BIL(P) col=ReadSample(P); w=exp(-(abs(Luma(col)-cLuma)*lumaW+length(col-center)*chromaW)); sumC+=col*w; sumW+=w;
        BIL(A0) BIL(A1) BIL(A2) BIL(A3)
        if (SampleQuality >= 1) { BIL(B0) BIL(B1) BIL(B2) BIL(B3) }
        if (SampleQuality >= 2) { BIL(C0) BIL(C1) BIL(C2) BIL(C3) }
        if (SampleQuality >= 3) { BIL(D0) BIL(D1) BIL(D2) BIL(D3) }
        #undef BIL
    }

    // ── GAUSSIAN ──────────────────────────────────────────────
    else if (FilterType == 1)
    {
        float w; float3 col;
        #define GAU(P) col=ReadSample(P); { float2 dd=(P-uv)/ReShade::PixelSize; w=exp(-dot(dd,dd)/(2.0*sigma*sigma)); } sumC+=col*w; sumW+=w;
        GAU(A0) GAU(A1) GAU(A2) GAU(A3)
        if (SampleQuality >= 1) { GAU(B0) GAU(B1) GAU(B2) GAU(B3) }
        if (SampleQuality >= 2) { GAU(C0) GAU(C1) GAU(C2) GAU(C3) }
        if (SampleQuality >= 3) { GAU(D0) GAU(D1) GAU(D2) GAU(D3) }
        #undef GAU
    }

    // ── MEAN ──────────────────────────────────────────────────
    else if (FilterType == 2)
    {
        sumC += ReadSample(A0)+ReadSample(A1)+ReadSample(A2)+ReadSample(A3); sumW += 4.0;
        if (SampleQuality >= 1) { sumC += ReadSample(B0)+ReadSample(B1)+ReadSample(B2)+ReadSample(B3); sumW += 4.0; }
        if (SampleQuality >= 2) { sumC += ReadSample(C0)+ReadSample(C1)+ReadSample(C2)+ReadSample(C3); sumW += 4.0; }
        if (SampleQuality >= 3) { sumC += ReadSample(D0)+ReadSample(D1)+ReadSample(D2)+ReadSample(D3); sumW += 4.0; }
    }

    // ── NLM-LITE ──────────────────────────────────────────────
    else if (FilterType == 3)
    {
        float w; float3 col;
        #define NLM(P) col=ReadSample(P); w=NLMWeight(P,uv,h2); sumC+=col*w; sumW+=w;
        NLM(A0) NLM(A1) NLM(A2) NLM(A3)
        if (SampleQuality >= 1) { NLM(B0) NLM(B1) NLM(B2) NLM(B3) }
        if (SampleQuality >= 2) { NLM(C0) NLM(C1) NLM(C2) NLM(C3) }
        if (SampleQuality >= 3) { NLM(D0) NLM(D1) NLM(D2) NLM(D3) }
        #undef NLM
    }

    // ── MEDIAN-APPROX ─────────────────────────────────────────
    else if (FilterType == 4)
    {
        float3 cMin=center, cMax=center;
        float3 s0=ReadSample(A0),s1=ReadSample(A1),s2=ReadSample(A2),s3=ReadSample(A3);
        sumC=center+s0+s1+s2+s3; sumW=5.0;
        cMin=min(min(min(min(cMin,s0),s1),s2),s3);
        cMax=max(max(max(max(cMax,s0),s1),s2),s3);
        if (SampleQuality>=1){float3 e0=ReadSample(B0),e1=ReadSample(B1),e2=ReadSample(B2),e3=ReadSample(B3); sumC+=e0+e1+e2+e3; sumW+=4.0; cMin=min(min(min(min(cMin,e0),e1),e2),e3); cMax=max(max(max(max(cMax,e0),e1),e2),e3);}
        if (SampleQuality>=2){float3 f0=ReadSample(C0),f1=ReadSample(C1),f2=ReadSample(C2),f3=ReadSample(C3); sumC+=f0+f1+f2+f3; sumW+=4.0; cMin=min(min(min(min(cMin,f0),f1),f2),f3); cMax=max(max(max(max(cMax,f0),f1),f2),f3);}
        if (SampleQuality>=3){float3 g0=ReadSample(D0),g1=ReadSample(D1),g2=ReadSample(D2),g3=ReadSample(D3); sumC+=g0+g1+g2+g3; sumW+=4.0; cMin=min(min(min(min(cMin,g0),g1),g2),g3); cMax=max(max(max(max(cMax,g0),g1),g2),g3);}
        float3 softMed = (sumC-cMin-cMax) / max(sumW-2.0, 1.0);
        float  ext = saturate(length(center-softMed)*10.0);
        return lerp(center, softMed, ext);
    }

    return sumC / sumW;
}

// ─────────────────────────────────────────────────────────────
//  FAST NOISE REDUCTION
// ─────────────────────────────────────────────────────────────

float3 FastNoiseReduce(float2 uv, float3 denoised, float strength)
{
    if (strength <= 0.0) return denoised;
    float2 px = ReShade::PixelSize;
    float3 avg =
        tex2D(ReShade::BackBuffer, uv+float2(-px.x,-px.y)).rgb +
        tex2D(ReShade::BackBuffer, uv+float2( 0.0, -px.y)).rgb +
        tex2D(ReShade::BackBuffer, uv+float2( px.x,-px.y)).rgb +
        tex2D(ReShade::BackBuffer, uv+float2(-px.x, 0.0 )).rgb +
        tex2D(ReShade::BackBuffer, uv+float2( px.x, 0.0 )).rgb +
        tex2D(ReShade::BackBuffer, uv+float2(-px.x, px.y)).rgb +
        tex2D(ReShade::BackBuffer, uv+float2( 0.0,  px.y)).rgb +
        tex2D(ReShade::BackBuffer, uv+float2( px.x, px.y)).rgb;
    avg /= 8.0;
    float srcLuma = Luma(tex2D(ReShade::BackBuffer, uv).rgb);
    float variance = abs(srcLuma - Luma(avg));
    float blend    = saturate(variance * 8.0) * strength;
    return lerp(denoised, avg, blend);
}

// ─────────────────────────────────────────────────────────────
//  SHARPNESS
// ─────────────────────────────────────────────────────────────

float3 Sharpen(float3 denoised, float3 blurApprox, float strength, float clampVal)
{
    float3 hf = denoised - blurApprox;
    return saturate(denoised + clamp(hf * strength, -clampVal, clampVal));
}

// ─────────────────────────────────────────────────────────────
//  PASS 1 — MAIN
// ─────────────────────────────────────────────────────────────

float4 PS_Main(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 original = tex2D(ReShade::BackBuffer, uv).rgb;
    if (!EnableDenoiser) return float4(original, 1.0);

    float  depth = ReShade::GetLinearizedDepth(uv);
    float3 zw    = ZoneWeights(depth);

    if (DebugMode == 1) return float4(depth, depth, depth, 1.0);
    if (DebugMode == 2) return float4(zw.x, zw.y, zw.z, 1.0);

    // Spatial denoise per zone
    float3 dNear = Denoise(uv, NearRadius, NearLuma, NearChroma);
    float3 dMid  = Denoise(uv, MidRadius,  MidLuma,  MidChroma);
    float3 dFar  = Denoise(uv, FarRadius,  FarLuma,  FarChroma);

    // Fast noise reduction
    dNear = FastNoiseReduce(uv, dNear, NearFastNoise);
    dMid  = FastNoiseReduce(uv, dMid,  MidFastNoise);
    dFar  = FastNoiseReduce(uv, dFar,  FarFastNoise);

    // Zone-weighted blend
    float3 outNear  = lerp(original, dNear, NearStrength);
    float3 outMid   = lerp(original, dMid,  MidStrength);
    float3 outFar   = lerp(original, dFar,  FarStrength);
    float3 denoised = outNear * zw.x + outMid * zw.y + outFar * zw.z;

    if (DebugMode == 3) return float4(denoised, 1.0);

    float3 output = denoised;

    // Temporal stabilization
    if (EnableTemporal)
    {
        float3 prev     = tex2D(sampStabilized, uv).rgb;
        float  prevLuma = tex2D(sampPrevLuma,   uv).r;
        float  currLuma = Luma(denoised);

        float lumaDiff  = abs(currLuma - prevLuma);
        float motFactor = saturate(lumaDiff / max(MotionRejectThreshold, 0.001));
        float motReduce = motFactor * MotionRejectStrength;

        float zoneJitter = zw.x * NearJitter + zw.y * MidJitter + zw.z * FarJitter;

        float flickerAdd = 0.0;
        if (lumaDiff > FlickerThreshold)
            flickerAdd = FlickerDamp * saturate((lumaDiff - FlickerThreshold) / max(FlickerThreshold, 0.001));

        float zoneStab = zw.x * NearNoiseStab + zw.y * MidNoiseStab + zw.z * FarNoiseStab;
        float variance = length(denoised - prev);
        float stabAdd  = 0.0;
        if (variance > NoiseFloorClamp)
            stabAdd = zoneStab * saturate((variance - NoiseFloorClamp) / max(NoiseFloorClamp, 0.001));

        float2 px = ReShade::PixelSize;
        float3 microAvg =
            tex2D(ReShade::BackBuffer, uv+float2( px.x, 0.0)).rgb +
            tex2D(ReShade::BackBuffer, uv+float2(-px.x, 0.0)).rgb +
            tex2D(ReShade::BackBuffer, uv+float2( 0.0,  px.y)).rgb +
            tex2D(ReShade::BackBuffer, uv+float2( 0.0, -px.y)).rgb;
        microAvg /= 4.0;
        float microSim = saturate(1.0 - length(denoised - microAvg) * 14.0);
        float3 microOut = lerp(denoised, microAvg, MicroJitterDamp * microSim);

        float3 w0=tex2D(ReShade::BackBuffer,uv+float2( 4.0*px.x, 0.0)).rgb;
        float3 w1=tex2D(ReShade::BackBuffer,uv+float2(-4.0*px.x, 0.0)).rgb;
        float3 w2=tex2D(ReShade::BackBuffer,uv+float2( 0.0, 4.0*px.y)).rgb;
        float3 w3=tex2D(ReShade::BackBuffer,uv+float2( 0.0,-4.0*px.y)).rgb;
        float  wideVar  = (length(w0-denoised)+length(w1-denoised)+length(w2-denoised)+length(w3-denoised))*0.25;
        float  shakeAdd = ShakeDamp * saturate(wideVar * 5.0);

        float totalBlend = (TemporalBlend + zoneJitter + flickerAdd + stabAdd + shakeAdd) * StabilizeSpeed;
        totalBlend = totalBlend * (1.0 - motReduce);
        totalBlend = saturate(totalBlend);

        float3 stabilized = lerp(microOut, prev, totalBlend);

        // Anti-ghosting clamp from denoised zone values
        float3 nMin = min(min(min(dNear, dMid), dFar), denoised);
        float3 nMax = max(max(max(dNear, dMid), dFar), denoised);
        stabilized = clamp(stabilized, nMin, nMax);

        output = stabilized;

        if (DebugMode == 4) return float4(totalBlend, totalBlend, totalBlend, 1.0);
        if (DebugMode == 5)
        {
            float fnMask = zw.x*NearFastNoise + zw.y*MidFastNoise + zw.z*FarFastNoise;
            float v = abs(Luma(tex2D(ReShade::BackBuffer, uv).rgb) - Luma(microAvg)) * 8.0;
            return float4(v * fnMask, v * 0.4, 0.0, 1.0);
        }
    }

    if (EnableSharpness)
    {
        float3 blurApprox = lerp(outNear*zw.x + outMid*zw.y + outFar*zw.z, output, 0.5);
        float  sharpScale = zw.x * SharpNearScale + zw.y * 1.0 + zw.z * SharpFarScale;
        output = Sharpen(output, blurApprox, SharpStrength * sharpScale, SharpClamp);
    }

    output = lerp(original, output, GlobalMix);
    return float4(output, 1.0);
}

// ─────────────────────────────────────────────────────────────
//  PASS 2 — Save stabilized frame to history
// ─────────────────────────────────────────────────────────────

float4 PS_SaveHistory(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return tex2D(ReShade::BackBuffer, uv);
}

// ─────────────────────────────────────────────────────────────
//  PASS 3 — Save luma history for flicker & SVGF detection
// ─────────────────────────────────────────────────────────────

float PS_SaveLuma(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return Luma(tex2D(sampStabilized, uv).rgb);
}

// ─────────────────────────────────────────────────────────────
//  TECHNIQUE
// ─────────────────────────────────────────────────────────────

technique AMDenoiser_Pro
<
    ui_label   = "AMDenoiser Pro  v5";
    ui_tooltip =
        "8 filter types including 3 strong distant-noise filters.\n\n"
        "For distant shaky noise, try these in order:\n"
        "  5 · Kuwahara         foliage / terrain shimmer\n"
        "  7 · SVGF-Lite        horizon / edge shake (best overall)\n"
        "  6 · Bilateral-Temporal  persistent grass/tree jitter\n\n"
        "Setup: Debug > Zone Overlay -> set boundaries -> pick filter -> tune Far zone.";
>
{
    pass Main
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_Main;
    }
    pass SaveHistory
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_SaveHistory;
        RenderTarget = texStabilized;
    }
    pass SaveLuma
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_SaveLuma;
        RenderTarget = texPrevLuma;
    }
}
