
// ============================================================
//  DepthFogRemoval.fx
//  Depth-based Volumetric Fog Removal for ReShade
//  Based on Clarity.fx by Ioxa — extended with depth sampling,
//  per-zone fog stripping, dehaze, contrast recovery, and
//  distance sharpening.
// ============================================================

#include "ReShadeUI.fxh"
#include "ReShade.fxh"

// ------------------------------------------------------------
//  CATEGORY: Depth Zone Setup
// ------------------------------------------------------------

uniform float DepthNearEnd
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Depth Zones";
    ui_label    = "Near Zone End (depth)";
    ui_min = 0.00; ui_max = 1.00; ui_step = 0.01;
    ui_tooltip  = "Depth value where the Near zone ends and Mid zone begins.\n"
                  "0 = camera, 1 = far clip. Typical: 0.05–0.15";
> = 0.08;

uniform float DepthMidEnd
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Depth Zones";
    ui_label    = "Mid Zone End (depth)";
    ui_min = 0.00; ui_max = 1.00; ui_step = 0.01;
    ui_tooltip  = "Depth value where the Mid zone ends and Far zone begins.\n"
                  "Typical: 0.30–0.60";
> = 0.40;

uniform float DepthFarEnd
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Depth Zones";
    ui_label    = "Far Zone End (depth)";
    ui_min = 0.00; ui_max = 1.00; ui_step = 0.01;
    ui_tooltip  = "Depth value beyond which the Far zone effect is held constant.\n"
                  "Typical: 0.70–1.00";
> = 0.90;

uniform bool DepthDebugZones
<
    ui_category = "Depth Zones";
    ui_label    = "Debug: Visualise Depth Zones";
    ui_tooltip  = "Colours the screen by zone: Red=Near, Green=Mid, Blue=Far.";
> = false;

// ------------------------------------------------------------
//  CATEGORY: Per-Zone Fog Removal Strength
// ------------------------------------------------------------

uniform float FogRemoveNear
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Fog Removal — Per Zone";
    ui_label    = "Near Zone Fog Removal";
    ui_min = 0.00; ui_max = 2.00; ui_step = 0.01;
    ui_tooltip  = "How aggressively fog/haze is stripped from the Near zone.\n"
                  "0 = no change. Keep low to avoid indoor over-correction.";
> = 0.20;

uniform float FogRemoveMid
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Fog Removal — Per Zone";
    ui_label    = "Mid Zone Fog Removal";
    ui_min = 0.00; ui_max = 2.00; ui_step = 0.01;
    ui_tooltip  = "Fog removal strength for the Mid zone.\n"
                  "This zone usually benefits most — raise first.";
> = 0.80;

uniform float FogRemoveFar
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Fog Removal — Per Zone";
    ui_label    = "Far Zone Fog Removal";
    ui_min = 0.00; ui_max = 2.00; ui_step = 0.01;
    ui_tooltip  = "Fog removal for distant scenery.\n"
                  "High values reclaim horizon detail but can introduce colour shifts.";
> = 1.20;

// ------------------------------------------------------------
//  CATEGORY: Dehaze (Atmospheric Scattering Removal)
// ------------------------------------------------------------

uniform float DehazeStrength
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Dehaze";
    ui_label    = "Dehaze Strength";
    ui_min = 0.00; ui_max = 1.00; ui_step = 0.01;
    ui_tooltip  = "Removes the bright atmospheric veil that flattens distant colours.\n"
                  "Works by estimating the airlight value and subtracting it.";
> = 0.45;

uniform float DehazeDepthStart
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Dehaze";
    ui_label    = "Dehaze Start Depth";
    ui_min = 0.00; ui_max = 1.00; ui_step = 0.01;
    ui_tooltip  = "Dehaze gradually ramps in from this depth onwards.\n"
                  "Set above 0 to leave foreground untouched.";
> = 0.10;

uniform float3 FogColour
<
    ui_category = "Dehaze";
    ui_label    = "Estimated Fog / Airlight Colour";
    ui_type     = "color";
    ui_tooltip  = "The colour of the volumetric fog or haze you want to remove.\n"
                  "Sample the brightest foggy area for best results.";
> = float3(0.78, 0.82, 0.86);

// ------------------------------------------------------------
//  CATEGORY: Distance Clarity (Unsharp Mask)
// ------------------------------------------------------------

uniform int ClarityRadius
< __UNIFORM_SLIDER_INT1
    ui_category = "Distance Clarity";
    ui_label    = "Blur Radius (clarity kernel)";
    ui_min = 0; ui_max = 4; ui_step = 1;
    ui_tooltip  = "[0–4] Larger values = wider unsharp-mask kernel = more macro contrast.";
> = 3;

uniform float ClarityOffset
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Distance Clarity";
    ui_label    = "Blur Offset Scale";
    ui_min = 1.00; ui_max = 5.00; ui_step = 0.25;
    ui_tooltip  = "Scales the sample spacing of the clarity blur.";
> = 2.00;

uniform float ClarityStrengthNear
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Distance Clarity";
    ui_label    = "Near Zone Clarity Strength";
    ui_min = 0.00; ui_max = 3.00; ui_step = 0.05;
    ui_tooltip  = "Unsharp-mask clarity in the Near zone.";
> = 0.10;

uniform float ClarityStrengthMid
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Distance Clarity";
    ui_label    = "Mid Zone Clarity Strength";
    ui_min = 0.00; ui_max = 3.00; ui_step = 0.05;
    ui_tooltip  = "Unsharp-mask clarity in the Mid zone.";
> = 0.40;

uniform float ClarityStrengthFar
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Distance Clarity";
    ui_label    = "Far Zone Clarity Strength";
    ui_min = 0.00; ui_max = 3.00; ui_step = 0.05;
    ui_tooltip  = "Unsharp-mask clarity in the Far zone. Boost to recover horizon sharpness.";
> = 1.20;

uniform float ClarityDarkIntensity
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Distance Clarity";
    ui_label    = "Dark Halo Intensity";
    ui_min = 0.00; ui_max = 1.00; ui_step = 0.05;
    ui_tooltip  = "Strength of dark fringe halos from the clarity mask.";
> = 0.40;

uniform float ClarityLightIntensity
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Distance Clarity";
    ui_label    = "Light Halo Intensity";
    ui_min = 0.00; ui_max = 1.00; ui_step = 0.05;
    ui_tooltip  = "Strength of light fringe halos from the clarity mask.";
> = 0.00;

// ------------------------------------------------------------
//  CATEGORY: Contrast & Colour Recovery
// ------------------------------------------------------------

uniform float ContrastRecovery
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Contrast & Colour Recovery";
    ui_label    = "Contrast Recovery";
    ui_min = 0.00; ui_max = 2.00; ui_step = 0.05;
    ui_tooltip  = "Restores midtone contrast crushed by fog. Applied per-zone via depth.";
> = 0.50;

uniform float SaturationBoost
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Contrast & Colour Recovery";
    ui_label    = "Saturation Boost";
    ui_min = 0.00; ui_max = 2.00; ui_step = 0.05;
    ui_tooltip  = "Recovers colour vibrancy lost to atmospheric grey-out.";
> = 0.40;

uniform float BlackPoint
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Contrast & Colour Recovery";
    ui_label    = "Black Point Lift";
    ui_min = 0.00; ui_max = 0.20; ui_step = 0.005;
    ui_tooltip  = "Crushes lifted blacks caused by fog scattering.\n"
                  "Raise until far-zone shadows look deep again.";
> = 0.04;

uniform float WhiteRecover
< __UNIFORM_SLIDER_FLOAT1
    ui_category = "Contrast & Colour Recovery";
    ui_label    = "Highlight Recovery";
    ui_min = 0.00; ui_max = 1.00; ui_step = 0.05;
    ui_tooltip  = "Pulls back blown highlights introduced by fog scattering on bright skies.";
> = 0.25;

// ------------------------------------------------------------
//  CATEGORY: Blend Mode (Clarity)
// ------------------------------------------------------------

uniform int ClarityBlendMode
<
    ui_category = "Clarity Blend";
    ui_type     = "combo";
    ui_label    = "Clarity Blend Mode";
    ui_items    = "Soft Light\0Overlay\0Hard Light\0Multiply\0Vivid Light\0Linear Light\0Addition\0";
    ui_tooltip  = "How the clarity mask is composited onto the image.";
> = 2;

// ------------------------------------------------------------
//  CATEGORY: Debug / Mask Views
// ------------------------------------------------------------

uniform bool ViewClarityMask
<
    ui_category = "Debug";
    ui_label    = "View Clarity Mask";
    ui_tooltip  = "Shows the raw clarity contrast mask.";
> = false;

uniform bool ViewDepthMap
<
    ui_category = "Debug";
    ui_label    = "View Depth Map";
    ui_tooltip  = "Shows the raw depth buffer values.";
> = false;

// ============================================================
//  TEXTURES & SAMPLERS
// ============================================================

texture DFR_BlurTex1 < pooled = true; > { Width = BUFFER_WIDTH  * 0.5; Height = BUFFER_HEIGHT * 0.5; Format = R8; };
texture DFR_BlurTex2                   { Width = BUFFER_WIDTH  * 0.5; Height = BUFFER_HEIGHT * 0.5; Format = R8; };
texture DFR_BlurTex3 < pooled = true; > { Width = BUFFER_WIDTH  * 0.25; Height = BUFFER_HEIGHT * 0.25; Format = R8; };

sampler sBlur1 { Texture = DFR_BlurTex1; };
sampler sBlur2 { Texture = DFR_BlurTex2; };
sampler sBlur3 { Texture = DFR_BlurTex3; };

// ============================================================
//  HELPER: Gaussian blur kernel lookup
// ============================================================

// Applies a 1-D separated Gaussian pass.
// dir = (1,0) or (0,1). Samples from 'samp'.
float GaussianBlur1D(sampler samp, float2 uv, float2 dir)
{
    float color = 0.0;

    if(ClarityRadius == 0)
    {
        float offset[4] = { 0.0, 1.1824255238, 3.0293122308, 5.0040701377 };
        float weight[4] = { 0.39894, 0.2959599993, 0.0045656525, 0.00000149278686458842 };
        color = tex2D(samp, uv).r * weight[0];
        [loop] for(int i=1;i<4;++i){
            color += tex2D(samp, uv + dir * offset[i] * ClarityOffset).r * weight[i];
            color += tex2D(samp, uv - dir * offset[i] * ClarityOffset).r * weight[i];
        }
    }
    else if(ClarityRadius == 1)
    {
        float offset[6] = { 0.0,1.4584295168,3.40398480678,5.3518057801,7.302940716,9.2581597095 };
        float weight[6] = { 0.13298,0.23227575,0.1353261595,0.0511557427,0.01253922,0.0019913644 };
        color = tex2D(samp, uv).r * weight[0];
        [loop] for(int i=1;i<6;++i){
            color += tex2D(samp, uv + dir * offset[i] * ClarityOffset).r * weight[i];
            color += tex2D(samp, uv - dir * offset[i] * ClarityOffset).r * weight[i];
        }
    }
    else if(ClarityRadius == 2)
    {
        float offset[11] = { 0.0,1.4895848401,3.4757135714,5.4618796741,7.4481042327,9.4344079746,11.420811147,13.4073334,15.3939936778,17.3808101174,19.3677999584 };
        float weight[11] = { 0.06649,0.1284697563,0.111918249,0.0873132676,0.0610011113,0.0381655709,0.0213835661,0.0107290241,0.0048206869,0.0019396469,0.0006988718 };
        color = tex2D(samp, uv).r * weight[0];
        [loop] for(int i=1;i<11;++i){
            color += tex2D(samp, uv + dir * offset[i] * ClarityOffset).r * weight[i];
            color += tex2D(samp, uv - dir * offset[i] * ClarityOffset).r * weight[i];
        }
    }
    else if(ClarityRadius == 3)
    {
        float offset[15] = { 0.0,1.4953705027,3.4891992113,5.4830312105,7.4768683759,9.4707125766,11.4645656736,13.4584295168,15.4523059431,17.4461967743,19.4401038149,21.43402885,23.4279736431,25.4219399344,27.4159294386 };
        float weight[15] = { 0.0443266667,0.0872994708,0.0820892038,0.0734818355,0.0626171681,0.0507956191,0.0392263968,0.0288369812,0.0201808877,0.0134446557,0.0085266392,0.0051478359,0.0029586248,0.0016187257,0.0008430913 };
        color = tex2D(samp, uv).r * weight[0];
        [loop] for(int i=1;i<15;++i){
            color += tex2D(samp, uv + dir * offset[i] * ClarityOffset).r * weight[i];
            color += tex2D(samp, uv - dir * offset[i] * ClarityOffset).r * weight[i];
        }
    }
    else // radius 4
    {
        float offset[18] = { 0.0,1.4953705027,3.4891992113,5.4830312105,7.4768683759,9.4707125766,11.4645656736,13.4584295168,15.4523059431,17.4461967743,19.4661974725,21.4627427973,23.4592916956,25.455844494,27.4524015179,29.4489630909,31.445529535,33.4421011704 };
        float weight[18] = { 0.033245,0.0659162217,0.0636705814,0.0598194658,0.0546642566,0.0485871646,0.0420045997,0.0353207015,0.0288880982,0.0229808311,0.0177815511,0.013382297,0.0097960001,0.0069746748,0.0048301008,0.0032534598,0.0021315311,0.0013582974 };
        color = tex2D(samp, uv).r * weight[0];
        [loop] for(int i=1;i<18;++i){
            color += tex2D(samp, uv + dir * offset[i] * ClarityOffset).r * weight[i];
            color += tex2D(samp, uv - dir * offset[i] * ClarityOffset).r * weight[i];
        }
    }
    return color;
}

// ============================================================
//  HELPER: blend mode (same set as original Clarity)
// ============================================================
float ApplyBlend(float luma, float sharp)
{
    float result = sharp;
    if(ClarityBlendMode == 0) // Soft Light
        result = lerp(2*luma*sharp + luma*luma*(1.0-2*sharp), 2*luma*(1.0-sharp)+pow(abs(luma),0.5)*(2*sharp-1.0), step(0.49,sharp));
    else if(ClarityBlendMode == 1) // Overlay
        result = lerp(2*luma*sharp, 1.0-2*(1.0-luma)*(1.0-sharp), step(0.50,luma));
    else if(ClarityBlendMode == 2) // Hard Light
        result = lerp(2*luma*sharp, 1.0-2*(1.0-luma)*(1.0-sharp), step(0.50,sharp));
    else if(ClarityBlendMode == 3) // Multiply
        result = saturate(2*luma*sharp);
    else if(ClarityBlendMode == 4) // Vivid Light
        result = lerp(2*luma*sharp, luma/(2*(1-sharp)+0.0001), step(0.5,sharp));
    else if(ClarityBlendMode == 5) // Linear Light
        result = luma + 2.0*sharp - 1.0;
    else                            // Addition
        result = saturate(luma + (sharp - 0.5));
    return result;
}

// ============================================================
//  HELPER: depth to [0,1] zone weight
// ============================================================
// Returns weights for (near, mid, far) zones. They blend
// smoothly across the zone boundaries so there are no hard lines.

float3 ZoneWeights(float depth)
{
    // Smooth zone membership with 5% overlap
    float blend = 0.05;
    float wNear = smoothstep(DepthNearEnd + blend, DepthNearEnd - blend, depth);
    float wFar  = smoothstep(DepthMidEnd  - blend, DepthMidEnd  + blend, depth)
                * smoothstep(DepthFarEnd  + blend, DepthFarEnd  - blend, depth + 0.0001);
    float wMid  = saturate(1.0 - wNear - wFar);
    return float3(wNear, wMid, wFar);
}

// ============================================================
//  PASS 1  — horizontal blur of luma (half-res)
// ============================================================
float PS_BlurH(in float4 pos : SV_Position, in float2 uv : TEXCOORD) : COLOR
{
    float3 rgb = tex2D(ReShade::BackBuffer, uv).rgb;
    float luma = dot(rgb, float3(0.32786885, 0.655737705, 0.0163934436));
    // Swap into temp: we need a luma texture at half res first.
    // We do a simple bilinear downsample here; the real blur is in pass 2/3.
    return luma;
}

// ============================================================
//  PASS 2  — horizontal Gaussian (half-res luma -> tex2)
// ============================================================
float PS_BlurH2(in float4 pos : SV_Position, in float2 uv : TEXCOORD) : COLOR
{
    return GaussianBlur1D(sBlur1, uv, float2(BUFFER_PIXEL_SIZE.x * 2.0, 0.0));
}

// ============================================================
//  PASS 3  — vertical Gaussian (tex2 -> quarter-res tex3)
// ============================================================
float PS_BlurV(in float4 pos : SV_Position, in float2 uv : TEXCOORD) : COLOR
{
    return GaussianBlur1D(sBlur2, uv, float2(0.0, BUFFER_PIXEL_SIZE.y * 2.0));
}

// ============================================================
//  FINAL PASS — fog removal + clarity + colour recovery
// ============================================================
float3 PS_FogRemoval(in float4 pos : SV_Position, in float2 uv : TEXCOORD) : COLOR
{
    // --- Source colour ---------------------------------------------------------
    float3 orig  = tex2D(ReShade::BackBuffer, uv).rgb;

    // --- Depth -----------------------------------------------------------------
    float  depth = ReShade::GetLinearizedDepth(uv);
    depth = saturate(depth);

    // Debug: raw depth map
    if(ViewDepthMap)
        return float3(depth, depth, depth);

    // --- Zone weights ----------------------------------------------------------
    float3 zones = ZoneWeights(depth); // (near, mid, far)
    float  wN = zones.x, wM = zones.y, wF = zones.z;

    // Debug: colour zones
    if(DepthDebugZones)
        return float3(wN, wM, wF);

    // --- Dehaze (atmospheric scattering removal) --------------------------------
    // Estimate transmission: t = 1 - depth*strength
    float  dehazeRamp   = smoothstep(DehazeDepthStart, saturate(DehazeDepthStart + 0.3), depth);
    float  transmission = saturate(1.0 - depth * DehazeStrength * dehazeRamp);
    // Dark Channel Prior inspired: J = (I - A) / max(t, 0.01) + A
    float3 dehazed = (orig - FogColour * (1.0 - transmission)) / max(transmission, 0.05);
    // Blend dehaze according to depth
    float dehazeBlend = dehazeRamp * DehazeStrength;
    float3 color = lerp(orig, saturate(dehazed), saturate(dehazeBlend));

    // --- Per-zone fog strip (luminance lift removal) ---------------------------
    // Fog raises the black point and compresses contrast. We reverse that.
    float fogStrength = wN * FogRemoveNear + wM * FogRemoveMid + wF * FogRemoveFar;
    // Estimate local fog lift: pixels should not be above 'pure white / fogFraction'
    float  fogLift   = depth * fogStrength * 0.20;  // 20% scale — conservative
    color = saturate((color - fogLift) / max(1.0 - fogLift, 0.001));

    // --- Black point & highlight correction ------------------------------------
    color = saturate((color - BlackPoint) / max(1.0 - BlackPoint - WhiteRecover * 0.15, 0.001));

    // --- Saturation boost (depth-weighted — farther = more) --------------------
    float luma  = dot(color, float3(0.32786885, 0.655737705, 0.0163934436));
    float3 chroma = color - luma;
    float satScale = 1.0 + SaturationBoost * (wM * 0.5 + wF * 1.0);
    color = saturate(luma + chroma * satScale);

    // --- Contrast recovery (S-curve midtone) -----------------------------------
    // depth-weighted: more contrast farther out
    float cStr = ContrastRecovery * (wM * 0.5 + wF * 1.0);
    color = saturate(color * (1.0 + cStr) - cStr * 0.5 * luma);

    // --- Clarity (unsharp mask) ------------------------------------------------
    // Blurred version from multi-pass Gaussian
    float blurred = tex2D(sBlur3, uv).r;
    luma = dot(color, float3(0.32786885, 0.655737705, 0.0163934436));
    chroma = color / max(luma, 0.001);

    float sharp = 1.0 - blurred;
    sharp = (luma + sharp) * 0.5;

    // Dark/light halo intensity
    float sharpMin = lerp(0.0, 1.0, smoothstep(0.0, 1.0, sharp));
    float sharpMax = sharpMin;
    sharpMin = lerp(sharp, sharpMin, ClarityDarkIntensity);
    sharpMax = lerp(sharp, sharpMax, ClarityLightIntensity);
    sharp = lerp(sharpMin, sharpMax, step(0.5, sharp));

    if(ViewClarityMask)
        return float3(sharp, sharp, sharp);

    // Apply blend mode
    float sharpBlended = ApplyBlend(luma, sharp);

    // Per-zone clarity strength
    float clarStr = wN * ClarityStrengthNear + wM * ClarityStrengthMid + wF * ClarityStrengthFar;
    float lumaOut = lerp(luma, sharpBlended, clarStr);

    color = lumaOut * chroma;

    return saturate(color);
}

// ============================================================
//  TECHNIQUE
// ============================================================
technique DepthFogRemoval
    < ui_label = "Depth Fog Removal";
      ui_tooltip = "Removes volumetric fog and haze using the depth buffer.\n"
                   "Provides per-zone fog stripping, dehaze, contrast & colour recovery,\n"
                   "and depth-weighted clarity sharpening."; >
{
    // Pass 1: half-res luma downsample (horizontal)
    pass BlurH1
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_BlurH;
        RenderTarget = DFR_BlurTex1;
    }

    // Pass 2: horizontal Gaussian
    pass BlurH2
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_BlurH2;
        RenderTarget = DFR_BlurTex2;
    }

    // Pass 3: vertical Gaussian (quarter-res)
    pass BlurV
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_BlurV;
        RenderTarget = DFR_BlurTex3;
    }

    // Final: fog removal + colour + clarity composite
    pass FogRemoval
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_FogRemoval;
    }
}
