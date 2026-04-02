/*
╔══════════════════════════════════════════════════════════════════════════════╗
║                         SkyFlora.fx  v1.0                                  ║
║           Blue Sky & Green Flora Enhancement Shader for ReShade             ║
║                                                                              ║
║  Features:                                                                  ║
║   • Targeted Hue/Saturation/Lightness for Sky Blues & Flora Greens          ║
║   • Multiple Tonemapping Profiles (Filmic, ACES, Reinhard, AgX)             ║
║   • Weather Presets: Sunny, Overcast, Cloudy                                ║
║   • Sky Refinement: gradient, haze, horizon glow                            ║
║   • Flora Refinement: leaf sheen, shadow depth, subsurface tint             ║
║   • Grass Detail: blade contrast, tip highlight, soil darkening             ║
╚══════════════════════════════════════════════════════════════════════════════╝
*/

#include "ReShade.fxh"

// ─────────────────────────────────────────────────────────────────────────────
//  NAMESPACE
// ─────────────────────────────────────────────────────────────────────────────
namespace SkyFlora {

// ─────────────────────────────────────────────────────────────────────────────
//  WEATHER PRESET  (drives automatic value blending when chosen)
// ─────────────────────────────────────────────────────────────────────────────
uniform int WeatherPreset <
    ui_type     = "combo";
    ui_label    = "Weather Preset";
    ui_tooltip  = "Quick color/tone profile. Set to Manual to use all sliders freely.";
    ui_items    = "Manual\0Sunny / Golden Hour\0Overcast / Diffuse\0Cloudy / Stormy\0";
    ui_category = "── Presets ──";
> = 0;

uniform float PresetBlend <
    ui_type     = "slider";
    ui_label    = "Preset Blend Strength";
    ui_tooltip  = "How strongly the preset overrides your manual values.";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Presets ──";
> = 1.0;

// ─────────────────────────────────────────────────────────────────────────────
//  TONEMAPPING
// ─────────────────────────────────────────────────────────────────────────────
uniform int TonemapProfile <
    ui_type     = "combo";
    ui_label    = "Tonemap Profile";
    ui_tooltip  = "Choose the overall tone curve style.";
    ui_items    = "None (Linear)\0Reinhard\0Filmic (Hable)\0ACES Fitted\0AgX Minimal\0Custom S-Curve\0";
    ui_category = "── Tonemapping ──";
> = 2;

uniform float Exposure <
    ui_type     = "slider";
    ui_label    = "Exposure (EV)";
    ui_min      = -3.0; ui_max = 3.0; ui_step = 0.05;
    ui_category = "── Tonemapping ──";
> = 0.0;

uniform float TonemapStrength <
    ui_type     = "slider";
    ui_label    = "Tonemap Strength";
    ui_tooltip  = "Blend between linear and chosen profile.";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Tonemapping ──";
> = 1.0;

uniform float Contrast <
    ui_type     = "slider";
    ui_label    = "Contrast";
    ui_min      = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Tonemapping ──";
> = 0.05;

uniform float3 ShadowColor <
    ui_type     = "color";
    ui_label    = "Shadow Tint";
    ui_category = "── Tonemapping ──";
> = float3(0.04, 0.06, 0.12);

uniform float3 MidtoneColor <
    ui_type     = "color";
    ui_label    = "Midtone Tint";
    ui_category = "── Tonemapping ──";
> = float3(0.50, 0.50, 0.50);

uniform float3 HighlightColor <
    ui_type     = "color";
    ui_label    = "Highlight Tint";
    ui_category = "── Tonemapping ──";
> = float3(1.00, 0.97, 0.88);

uniform float ShadowLift <
    ui_type     = "slider";
    ui_label    = "Shadow Lift";
    ui_min      = -0.2; ui_max = 0.2; ui_step = 0.005;
    ui_category = "── Tonemapping ──";
> = 0.0;

uniform float HighlightCompress <
    ui_type     = "slider";
    ui_label    = "Highlight Compression";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Tonemapping ──";
> = 0.15;

// ─────────────────────────────────────────────────────────────────────────────
//  GLOBAL COLOR
// ─────────────────────────────────────────────────────────────────────────────
uniform float GlobalSaturation <
    ui_type     = "slider";
    ui_label    = "Global Saturation";
    ui_min      = -1.0; ui_max = 2.0; ui_step = 0.01;
    ui_category = "── Global Color ──";
> = 0.10;

uniform float GlobalTemperature <
    ui_type     = "slider";
    ui_label    = "Color Temperature (warm +/cool -)";
    ui_min      = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Global Color ──";
> = 0.0;

uniform float GlobalTint <
    ui_type     = "slider";
    ui_label    = "Tint (green +/magenta -)";
    ui_min      = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Global Color ──";
> = 0.0;

uniform float Vibrance <
    ui_type     = "slider";
    ui_label    = "Vibrance (protects skin)";
    ui_min      = -1.0; ui_max = 2.0; ui_step = 0.01;
    ui_category = "── Global Color ──";
> = 0.15;

// ─────────────────────────────────────────────────────────────────────────────
//  SKY  ─  HUE / SAT / LUM
// ─────────────────────────────────────────────────────────────────────────────
uniform bool  SkyEnable <
    ui_label    = "Enable Sky Correction";
    ui_category = "── Sky (Blues) ──";
> = true;

uniform float SkyHueCenter <
    ui_type     = "slider";
    ui_label    = "Sky Hue Center (°)";
    ui_tooltip  = "Target hue. 210-230 covers typical sky blue.";
    ui_min      = 0.0; ui_max = 360.0; ui_step = 1.0;
    ui_category = "── Sky (Blues) ──";
> = 215.0;

uniform float SkyHueRange <
    ui_type     = "slider";
    ui_label    = "Sky Hue Range (°)";
    ui_tooltip  = "Width of hue selection.";
    ui_min      = 5.0; ui_max = 90.0; ui_step = 1.0;
    ui_category = "── Sky (Blues) ──";
> = 40.0;

uniform float SkyHueShift <
    ui_type     = "slider";
    ui_label    = "Sky Hue Shift (°)";
    ui_min      = -60.0; ui_max = 60.0; ui_step = 0.5;
    ui_category = "── Sky (Blues) ──";
> = 0.0;

uniform float SkySatBoost <
    ui_type     = "slider";
    ui_label    = "Sky Saturation Boost";
    ui_min      = -1.0; ui_max = 2.0; ui_step = 0.01;
    ui_category = "── Sky (Blues) ──";
> = 0.20;

uniform float SkyLumBoost <
    ui_type     = "slider";
    ui_label    = "Sky Luminance Boost";
    ui_min      = -0.5; ui_max = 0.5; ui_step = 0.01;
    ui_category = "── Sky (Blues) ──";
> = 0.0;

uniform float SkyLumThreshold <
    ui_type     = "slider";
    ui_label    = "Sky Lum Threshold (avoid ground)";
    ui_tooltip  = "Only apply sky tweaks to pixels brighter than this.";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Sky (Blues) ──";
> = 0.30;

// Sky Refinement
uniform float SkyHazeStrength <
    ui_type     = "slider";
    ui_label    = "Horizon Haze Strength";
    ui_tooltip  = "Adds a warm desaturated haze near bright horizon.";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Sky (Blues) ──";
> = 0.10;

uniform float3 SkyHazeColor <
    ui_type     = "color";
    ui_label    = "Horizon Haze Color";
    ui_category = "── Sky (Blues) ──";
> = float3(0.92, 0.82, 0.68);

uniform float SkyZenithDarken <
    ui_type     = "slider";
    ui_label    = "Zenith Darkening";
    ui_tooltip  = "Darkens very bright/white sky top for realism.";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Sky (Blues) ──";
> = 0.08;

uniform float CloudDesaturate <
    ui_type     = "slider";
    ui_label    = "Cloud/White-Sky Desaturate";
    ui_tooltip  = "Pulls saturation from near-white sky pixels.";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Sky (Blues) ──";
> = 0.20;

// ─────────────────────────────────────────────────────────────────────────────
//  FLORA  ─  HUE / SAT / LUM
// ─────────────────────────────────────────────────────────────────────────────
uniform bool  FloraEnable <
    ui_label    = "Enable Flora Correction";
    ui_category = "── Flora (Greens) ──";
> = true;

uniform float FloraHueCenter <
    ui_type     = "slider";
    ui_label    = "Flora Hue Center (°)";
    ui_tooltip  = "Target hue. 95-130 covers foliage greens.";
    ui_min      = 0.0; ui_max = 360.0; ui_step = 1.0;
    ui_category = "── Flora (Greens) ──";
> = 110.0;

uniform float FloraHueRange <
    ui_type     = "slider";
    ui_label    = "Flora Hue Range (°)";
    ui_min      = 5.0; ui_max = 90.0; ui_step = 1.0;
    ui_category = "── Flora (Greens) ──";
> = 50.0;

uniform float FloraHueShift <
    ui_type     = "slider";
    ui_label    = "Flora Hue Shift (°)";
    ui_tooltip  = "+ = warmer/yellow, - = cooler/teal";
    ui_min      = -60.0; ui_max = 60.0; ui_step = 0.5;
    ui_category = "── Flora (Greens) ──";
> = -5.0;

uniform float FloraSatBoost <
    ui_type     = "slider";
    ui_label    = "Flora Saturation Boost";
    ui_min      = -1.0; ui_max = 2.0; ui_step = 0.01;
    ui_category = "── Flora (Greens) ──";
> = 0.25;

uniform float FloraLumBoost <
    ui_type     = "slider";
    ui_label    = "Flora Luminance Boost";
    ui_min      = -0.5; ui_max = 0.5; ui_step = 0.01;
    ui_category = "── Flora (Greens) ──";
> = 0.05;

// Flora Refinement
uniform float LeafSheen <
    ui_type     = "slider";
    ui_label    = "Leaf Sheen (highlight brightness)";
    ui_tooltip  = "Adds subtle specular-like brightening to bright greens.";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Flora (Greens) ──";
> = 0.12;

uniform float LeafShadowDepth <
    ui_type     = "slider";
    ui_label    = "Leaf Shadow Depth";
    ui_tooltip  = "Darkens shadowed greens for richer canopy depth.";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Flora (Greens) ──";
> = 0.15;

uniform float3 SubsurfaceTint <
    ui_type     = "color";
    ui_label    = "Subsurface Scatter Tint";
    ui_tooltip  = "Warm tint added to mid-lum greens simulating light through leaves.";
    ui_category = "── Flora (Greens) ──";
> = float3(0.55, 0.80, 0.20);

uniform float SubsurfaceStrength <
    ui_type     = "slider";
    ui_label    = "Subsurface Strength";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Flora (Greens) ──";
> = 0.10;

uniform float FloraYellowPull <
    ui_type     = "slider";
    ui_label    = "Autumn Yellow Pull";
    ui_tooltip  = "Shifts yellow-greens toward golden tones.";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Flora (Greens) ──";
> = 0.0;

// ─────────────────────────────────────────────────────────────────────────────
//  GRASS  ─  DETAIL REFINEMENT
// ─────────────────────────────────────────────────────────────────────────────
uniform bool  GrassEnable <
    ui_label    = "Enable Grass Refinement";
    ui_category = "── Grass Detail ──";
> = true;

uniform float GrassHueCenter <
    ui_type     = "slider";
    ui_label    = "Grass Hue Center (°)";
    ui_tooltip  = "Grass tends slightly yellower-green: 80-105";
    ui_min      = 0.0; ui_max = 360.0; ui_step = 1.0;
    ui_category = "── Grass Detail ──";
> = 92.0;

uniform float GrassHueRange <
    ui_type     = "slider";
    ui_label    = "Grass Hue Range (°)";
    ui_min      = 5.0; ui_max = 60.0; ui_step = 1.0;
    ui_category = "── Grass Detail ──";
> = 28.0;

uniform float GrassHueShift <
    ui_type     = "slider";
    ui_label    = "Grass Hue Shift (°)";
    ui_min      = -30.0; ui_max = 30.0; ui_step = 0.5;
    ui_category = "── Grass Detail ──";
> = 0.0;

uniform float GrassSatBoost <
    ui_type     = "slider";
    ui_label    = "Grass Saturation";
    ui_min      = -1.0; ui_max = 2.0; ui_step = 0.01;
    ui_category = "── Grass Detail ──";
> = 0.15;

uniform float GrassTipHighlight <
    ui_type     = "slider";
    ui_label    = "Grass Tip Highlight";
    ui_tooltip  = "Brightens high-lum grass pixels (blade tips catching light).";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Grass Detail ──";
> = 0.10;

uniform float GrassSoilDarken <
    ui_type     = "slider";
    ui_label    = "Soil/Base Darkening";
    ui_tooltip  = "Darkens low-lum grass pixels (soil between blades).";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Grass Detail ──";
> = 0.10;

uniform float3 GrassDryTint <
    ui_type     = "color";
    ui_label    = "Dry/Dead Grass Tint";
    ui_tooltip  = "Color added to desaturated low-lum grass.";
    ui_category = "── Grass Detail ──";
> = float3(0.72, 0.65, 0.30);

uniform float GrassDryAmount <
    ui_type     = "slider";
    ui_label    = "Dry Grass Amount";
    ui_min      = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_category = "── Grass Detail ──";
> = 0.0;

// ─────────────────────────────────────────────────────────────────────────────
//  OUTPUT
// ─────────────────────────────────────────────────────────────────────────────
uniform float GammaCorrOut <
    ui_type     = "slider";
    ui_label    = "Output Gamma";
    ui_min      = 0.5; ui_max = 2.5; ui_step = 0.01;
    ui_category = "── Output ──";
> = 1.0;

uniform bool  DebugMask <
    ui_label    = "DEBUG: Show Hue Selection Masks";
    ui_tooltip  = "Red = Sky mask, Green = Flora mask, Blue = Grass mask.";
    ui_category = "── Output ──";
> = false;

// ─────────────────────────────────────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────────────────────────────────────

float3 RGBtoHSL(float3 c)
{
    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float delta = maxC - minC;
    float L = (maxC + minC) * 0.5;
    float S = 0.0;
    float H = 0.0;

    if (delta > 1e-6)
    {
        S = delta / (1.0 - abs(2.0 * L - 1.0));
        if (maxC == c.r)      H = ((c.g - c.b) / delta);
        else if (maxC == c.g) H = ((c.b - c.r) / delta) + 2.0;
        else                  H = ((c.r - c.g) / delta) + 4.0;
        H = frac(H / 6.0) * 360.0;
    }
    return float3(H, S, L);
}

float3 HSLtoRGB(float3 hsl)
{
    float H = hsl.x, S = hsl.y, L = hsl.z;
    float C = (1.0 - abs(2.0 * L - 1.0)) * S;
    float X = C * (1.0 - abs(frac(H / 60.0) * 2.0 - 1.0));
    float m = L - C * 0.5;
    float3 rgb;
    if      (H < 60.0)  rgb = float3(C, X, 0);
    else if (H < 120.0) rgb = float3(X, C, 0);
    else if (H < 180.0) rgb = float3(0, C, X);
    else if (H < 240.0) rgb = float3(0, X, C);
    else if (H < 300.0) rgb = float3(X, 0, C);
    else                rgb = float3(C, 0, X);
    return saturate(rgb + m);
}

// Soft hue selection mask with feathered edges
float HueMask(float hue, float center, float range)
{
    float dist = abs(frac((hue - center + 540.0) / 360.0) * 360.0 - 180.0);
    return saturate(1.0 - dist / (range * 0.5));
}

// Luminance utility
float Luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ── Tonemap Profiles ──────────────────────────────────────────────────────────

float3 Reinhard(float3 x)       { return x / (x + 1.0); }

float3 HableFilmic(float3 x)
{
    const float A = 0.15, B = 0.50, C = 0.10, D = 0.20, E = 0.02, F = 0.30;
    return ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F)) - E/F;
}

float3 TonemapFilmic(float3 color)
{
    float3 curr = HableFilmic(color * 2.0);
    float3 whiteScale = 1.0 / HableFilmic(float3(11.2, 11.2, 11.2));
    return curr * whiteScale;
}

float3 TonemapACES(float3 x)
{
    // ACES fitted approximation (Narkowicz 2015)
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

float3 TonemapAgX(float3 x)
{
    // Minimal AgX-inspired log-sigmoid approximation
    x = max(x, 0.0);
    x = log2(x + 0.0001) * 0.18 + 0.5;
    x = 1.0 / (1.0 + exp(-6.0 * (x - 0.5)));
    return saturate(x);
}

float3 CustomSCurve(float3 x)
{
    // Smooth S-curve: preserves shadows/highlights better
    x = saturate(x);
    return x * x * (3.0 - 2.0 * x);
}

// ── Color Grading Lift/Gamma/Gain ────────────────────────────────────────────
float3 ApplyColorBalance(float3 c, float3 shadows, float3 mids, float3 highs, float shadowLift)
{
    float lum = Luma(c);
    float shadowW    = saturate(1.0 - lum * 2.0);
    float highlightW = saturate(lum * 2.0 - 1.0);
    float midW       = 1.0 - shadowW - highlightW;

    // Lift
    c += shadowLift * shadowW;

    // Tint by zone
    float3 tint = shadows * shadowW + mids * midW + highs * highlightW;
    // Map tint from [0,1] to [-0.5,0.5] offset
    tint = (tint - 0.5) * 0.15;
    return saturate(c + tint);
}

// ── Vibrance ─────────────────────────────────────────────────────────────────
float3 ApplyVibrance(float3 c, float vibrance)
{
    float lum = Luma(c);
    float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    float vib = (1.0 - sat) * vibrance;
    return lerp(float3(lum, lum, lum), c, 1.0 + vib);
}

// ── Temperature / Tint ───────────────────────────────────────────────────────
float3 ApplyWhiteBalance(float3 c, float temp, float tint)
{
    // temp: +warm (add red, remove blue)  tint: +green
    c.r += temp  * 0.10;
    c.b -= temp  * 0.10;
    c.g += tint  * 0.05;
    c.r -= tint  * 0.02;
    return saturate(c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRESET DATA
// ─────────────────────────────────────────────────────────────────────────────
struct PresetData {
    float exposure;
    float temperature;
    float tint;
    float saturation;
    float skyHueShift;
    float skySatBoost;
    float skyLumBoost;
    float floraHueShift;
    float floraSatBoost;
    float hazeStrength;
    float shadowLift;
    float contrast;
};

PresetData GetPreset(int idx)
{
    PresetData p;
    // Defaults (= manual)
    p.exposure       =  0.00; p.temperature   =  0.00; p.tint          =  0.00;
    p.saturation     =  0.10; p.skyHueShift   =  0.00; p.skySatBoost   =  0.20;
    p.skyLumBoost    =  0.00; p.floraHueShift = -5.00; p.floraSatBoost =  0.25;
    p.hazeStrength   =  0.10; p.shadowLift    =  0.00; p.contrast      =  0.05;

    if (idx == 1) // Sunny
    {
        p.exposure       =  0.10; p.temperature   =  0.25; p.tint          = -0.05;
        p.saturation     =  0.30; p.skyHueShift   = -5.00; p.skySatBoost   =  0.45;
        p.skyLumBoost    =  0.08; p.floraHueShift = -8.00; p.floraSatBoost =  0.40;
        p.hazeStrength   =  0.20; p.shadowLift    = -0.02; p.contrast      =  0.15;
    }
    else if (idx == 2) // Overcast
    {
        p.exposure       = -0.10; p.temperature   = -0.10; p.tint          =  0.02;
        p.saturation     = -0.05; p.skyHueShift   =  8.00; p.skySatBoost   = -0.10;
        p.skyLumBoost    = -0.05; p.floraHueShift =  5.00; p.floraSatBoost =  0.05;
        p.hazeStrength   =  0.05; p.shadowLift    =  0.04; p.contrast      = -0.05;
    }
    else if (idx == 3) // Cloudy/Stormy
    {
        p.exposure       = -0.20; p.temperature   = -0.20; p.tint          =  0.05;
        p.saturation     = -0.15; p.skyHueShift   = 15.00; p.skySatBoost   = -0.20;
        p.skyLumBoost    = -0.10; p.floraHueShift =  8.00; p.floraSatBoost = -0.05;
        p.hazeStrength   =  0.02; p.shadowLift    =  0.03; p.contrast      = -0.10;
    }
    return p;
}

// ─────────────────────────────────────────────────────────────────────────────
//  MAIN PASS
// ─────────────────────────────────────────────────────────────────────────────
float4 PS_SkyFlora(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, uv).rgb;

    // ── Load preset and blend ────────────────────────────────────────────────
    PresetData preset = GetPreset(WeatherPreset);
    float pb = (WeatherPreset == 0) ? 0.0 : PresetBlend;

    float e_exposure    = lerp(Exposure,         preset.exposure,       pb);
    float e_temp        = lerp(GlobalTemperature, preset.temperature,   pb);
    float e_tint        = lerp(GlobalTint,        preset.tint,          pb);
    float e_sat         = lerp(GlobalSaturation,  preset.saturation,    pb);
    float e_skyHShift   = lerp(SkyHueShift,       preset.skyHueShift,   pb);
    float e_skySat      = lerp(SkySatBoost,       preset.skySatBoost,   pb);
    float e_skyLum      = lerp(SkyLumBoost,       preset.skyLumBoost,   pb);
    float e_floraHShift = lerp(FloraHueShift,     preset.floraHueShift, pb);
    float e_floraSat    = lerp(FloraSatBoost,     preset.floraSatBoost, pb);
    float e_haze        = lerp(SkyHazeStrength,   preset.hazeStrength,  pb);
    float e_shadowLift  = lerp(ShadowLift,        preset.shadowLift,    pb);
    float e_contrast    = lerp(Contrast,          preset.contrast,      pb);

    // ── Exposure ─────────────────────────────────────────────────────────────
    color *= pow(2.0, e_exposure);

    // ── White Balance ────────────────────────────────────────────────────────
    color = ApplyWhiteBalance(color, e_temp, e_tint);

    // ── Tonemapping ──────────────────────────────────────────────────────────
    float3 toneMapped = color;
    if      (TonemapProfile == 1) toneMapped = Reinhard(color);
    else if (TonemapProfile == 2) toneMapped = TonemapFilmic(color);
    else if (TonemapProfile == 3) toneMapped = TonemapACES(color);
    else if (TonemapProfile == 4) toneMapped = TonemapAgX(color);
    else if (TonemapProfile == 5) toneMapped = CustomSCurve(color);

    color = lerp(color, toneMapped, TonemapStrength);
    color = saturate(color);

    // ── Contrast ─────────────────────────────────────────────────────────────
    color = saturate((color - 0.5) * (1.0 + e_contrast) + 0.5);

    // ── Highlight Compression ────────────────────────────────────────────────
    float lumC = Luma(color);
    color = lerp(color, color * (1.0 - HighlightCompress * smoothstep(0.7, 1.0, lumC)), HighlightCompress);

    // ── Shadow / Mid / Highlight Tint ────────────────────────────────────────
    color = ApplyColorBalance(color, ShadowColor, MidtoneColor, HighlightColor, e_shadowLift);

    // ── Global Saturation ────────────────────────────────────────────────────
    {
        float lum = Luma(color);
        color = lerp(float3(lum,lum,lum), color, 1.0 + e_sat);
        color = saturate(color);
    }

    // ── Vibrance ─────────────────────────────────────────────────────────────
    color = ApplyVibrance(color, Vibrance);

    // ─────────────────────────────────────────────────────────────────────────
    //  PER-HUE ADJUSTMENTS
    // ─────────────────────────────────────────────────────────────────────────
    float3 hsl = RGBtoHSL(color);
    float  H   = hsl.x, S = hsl.y, L = hsl.z;
    float  luma = Luma(color);

    // ── SKY mask ─────────────────────────────────────────────────────────────
    float skyMask = 0.0;
    if (SkyEnable)
    {
        skyMask = HueMask(H, SkyHueCenter, SkyHueRange);
        // Brightness gate: avoid dark blues (jeans, night shadows)
        skyMask *= smoothstep(SkyLumThreshold - 0.05, SkyLumThreshold + 0.15, luma);

        float3 skyHSL = hsl;

        // Hue shift
        skyHSL.x = frac((skyHSL.x + e_skyHShift) / 360.0) * 360.0;

        // Sat boost – scale existing sat
        float cloudW = smoothstep(0.05, 0.35, S); // low-sat = clouds
        skyHSL.y = saturate(skyHSL.y * (1.0 + e_skySat * cloudW));

        // Cloud desaturation
        float cloudPull = (1.0 - cloudW) * CloudDesaturate;
        skyHSL.y = saturate(skyHSL.y - cloudPull);

        // Lum
        skyHSL.z = saturate(skyHSL.z + e_skyLum);

        // Zenith darkening (very bright sky pixels)
        float zenithW = smoothstep(0.6, 0.95, L);
        skyHSL.z = saturate(skyHSL.z - SkyZenithDarken * zenithW);

        float3 skyRGB = HSLtoRGB(skyHSL);

        // Horizon haze: blend toward haze color for brighter pixels near white
        float hazeW = smoothstep(0.55, 0.90, L) * e_haze;
        skyRGB = lerp(skyRGB, SkyHazeColor, hazeW);

        color = lerp(color, skyRGB, skyMask);
    }

    // ── FLORA mask ───────────────────────────────────────────────────────────
    float floraMask = 0.0;
    if (FloraEnable)
    {
        // Re-sample HSL from possibly sky-modified color
        hsl = RGBtoHSL(color); H = hsl.x; S = hsl.y; L = hsl.z;
        floraMask = HueMask(H, FloraHueCenter, FloraHueRange);
        // Exclude very bright (sky reflection) and very dark pixels
        floraMask *= smoothstep(0.03, 0.12, L) * smoothstep(1.0, 0.7, L);

        float3 floraHSL = hsl;

        // Hue shift
        floraHSL.x = frac((floraHSL.x + e_floraHShift) / 360.0) * 360.0;

        // Saturation
        floraHSL.y = saturate(floraHSL.y * (1.0 + e_floraSat));

        // Lum
        floraHSL.z = saturate(floraHSL.z + FloraLumBoost);

        float3 floraRGB = HSLtoRGB(floraHSL);

        // Leaf sheen: brighten highlights
        float sheenW = smoothstep(0.5, 0.85, L) * LeafSheen;
        floraRGB = saturate(floraRGB + sheenW * 0.2);

        // Leaf shadow depth: deepen darks
        float shadowW2 = smoothstep(0.35, 0.05, L) * LeafShadowDepth;
        floraRGB = saturate(floraRGB - shadowW2 * 0.25);

        // Subsurface tint on mid-lum greens
        float ssW = smoothstep(0.15, 0.35, L) * smoothstep(0.75, 0.45, L) * SubsurfaceStrength;
        floraRGB = lerp(floraRGB, floraRGB * SubsurfaceTint * 2.0, ssW);
        floraRGB = saturate(floraRGB);

        // Autumn pull (shift yellow-greens gold)
        float yellowW = HueMask(H, 75.0, 30.0) * FloraYellowPull;
        floraHSL.x = frac((floraHSL.x + 20.0 * yellowW) / 360.0) * 360.0;
        floraHSL.y = saturate(floraHSL.y * (1.0 + 0.3 * yellowW));
        float3 autumnRGB = HSLtoRGB(floraHSL);
        floraRGB = lerp(floraRGB, autumnRGB, yellowW);

        color = lerp(color, saturate(floraRGB), floraMask);
    }

    // ── GRASS mask ───────────────────────────────────────────────────────────
    float grassMask = 0.0;
    if (GrassEnable)
    {
        hsl = RGBtoHSL(color); H = hsl.x; S = hsl.y; L = hsl.z;
        grassMask = HueMask(H, GrassHueCenter, GrassHueRange);
        // Keep low-to-mid luminance (ground level)
        grassMask *= smoothstep(0.02, 0.10, L) * smoothstep(0.75, 0.35, L);

        float3 grassHSL = hsl;
        grassHSL.x = frac((grassHSL.x + GrassHueShift) / 360.0) * 360.0;
        grassHSL.y = saturate(grassHSL.y * (1.0 + GrassSatBoost));
        float3 grassRGB = HSLtoRGB(grassHSL);

        // Tip highlight
        float tipW = smoothstep(0.45, 0.72, L) * GrassTipHighlight;
        grassRGB = saturate(grassRGB + tipW * 0.25);

        // Soil darkening
        float soilW = smoothstep(0.30, 0.08, L) * GrassSoilDarken;
        grassRGB = saturate(grassRGB - soilW * 0.30);

        // Dry grass tint (desaturated yellowy grass)
        float dryW = smoothstep(0.20, 0.05, S) * GrassDryAmount;
        grassRGB = lerp(grassRGB, GrassDryTint * L * 2.0, dryW);
        grassRGB = saturate(grassRGB);

        color = lerp(color, grassRGB, grassMask);
    }

    // ── Output Gamma ─────────────────────────────────────────────────────────
    color = pow(saturate(color), 1.0 / max(GammaCorrOut, 0.01));

    // ── Debug Mask View ───────────────────────────────────────────────────────
    if (DebugMask)
    {
        return float4(
            skyMask,
            floraMask,
            grassMask,
            1.0
        );
    }

    return float4(color, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
//  TECHNIQUE
// ─────────────────────────────────────────────────────────────────────────────
technique SkyFlora <
    ui_label   = "SkyFlora – Sky & Flora Enhancer";
    ui_tooltip = "Targeted hue grading for blue sky and green flora with weather presets and tonemapping.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_SkyFlora;
    }
}

} // namespace SkyFlora
