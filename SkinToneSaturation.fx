/**
 * ╔══════════════════════════════════════════════════════════════╗
 * ║           SKIN TONE SATURATION SHADER v1.0                  ║
 * ║           for ReShade 5.x+                                  ║
 * ║                                                              ║
 * ║  Detects skin tones across fair, medium, tan, and dark       ║
 * ║  complexions. Ignores pure reds and warm browns.             ║
 * ║  Allows selective desaturation or saturation of skin only.  ║
 * ╚══════════════════════════════════════════════════════════════╝
 */

#include "ReShade.fxh"

// ─────────────────────────────────────────────
//  UI PARAMETERS
// ─────────────────────────────────────────────

uniform float SaturationStrength <
    ui_type     = "slider";
    ui_label    = "Saturation Strength";
    ui_tooltip  = "Positive = boost skin saturation. Negative = desaturate skin. 0 = no change.";
    ui_min      = -2.0;
    ui_max      =  2.0;
    ui_step     =  0.01;
    ui_category = "Skin Tone Saturation";
> = 0.5;

uniform float SkinHueCenter <
    ui_type     = "slider";
    ui_label    = "Skin Hue Center";
    ui_tooltip  = "Center hue for skin detection (degrees). Default ~18 works for most skin tones.";
    ui_min      =  0.0;
    ui_max      = 50.0;
    ui_step     =  0.5;
    ui_category = "Skin Tone Saturation";
> = 18.0;

uniform float SkinHueRange <
    ui_type     = "slider";
    ui_label    = "Skin Hue Range";
    ui_tooltip  = "How wide a hue range counts as skin. Smaller = more precise.";
    ui_min      =  2.0;
    ui_max      = 30.0;
    ui_step     =  0.5;
    ui_category = "Skin Tone Saturation";
> = 14.0;

uniform float SkinSatMin <
    ui_type     = "slider";
    ui_label    = "Skin Min Saturation";
    ui_tooltip  = "Minimum HSV saturation for skin pixels. Filters out near-grey areas.";
    ui_min      = 0.0;
    ui_max      = 0.5;
    ui_step     = 0.01;
    ui_category = "Skin Tone Saturation";
> = 0.08;

uniform float SkinSatMax <
    ui_type     = "slider";
    ui_label    = "Skin Max Saturation";
    ui_tooltip  = "Maximum HSV saturation for skin pixels. Excludes vivid reds/oranges.";
    ui_min      = 0.2;
    ui_max      = 1.0;
    ui_step     = 0.01;
    ui_category = "Skin Tone Saturation";
> = 0.72;

uniform float SkinValMin <
    ui_type     = "slider";
    ui_label    = "Skin Min Brightness";
    ui_tooltip  = "Minimum HSV value (brightness) to consider as skin. Filters very dark pixels.";
    ui_min      = 0.05;
    ui_max      = 0.5;
    ui_step     = 0.01;
    ui_category = "Skin Tone Saturation";
> = 0.12;

uniform float SkinValMax <
    ui_type     = "slider";
    ui_label    = "Skin Max Brightness";
    ui_tooltip  = "Maximum HSV value for skin. Filters blown-out whites.";
    ui_min      = 0.5;
    ui_max      = 1.0;
    ui_step     = 0.01;
    ui_category = "Skin Tone Saturation";
> = 0.97;

uniform float MaskSoftness <
    ui_type     = "slider";
    ui_label    = "Mask Softness";
    ui_tooltip  = "Blends the skin mask edges smoothly. Higher = softer transitions.";
    ui_min      =  0.0;
    ui_max      =  1.0;
    ui_step     =  0.01;
    ui_category = "Skin Tone Saturation";
> = 0.5;

uniform bool  ShowMask <
    ui_label    = "Show Skin Mask (debug)";
    ui_tooltip  = "Overlays the detected skin mask in red to help tune settings.";
    ui_category = "Skin Tone Saturation";
> = false;

// ─────────────────────────────────────────────
//  HELPER FUNCTIONS
// ─────────────────────────────────────────────

// Convert linear RGB → HSV
float3 RGBtoHSV(float3 c)
{
    float cmax  = max(c.r, max(c.g, c.b));
    float cmin  = min(c.r, min(c.g, c.b));
    float delta = cmax - cmin;

    float h = 0.0;
    if (delta > 1e-6)
    {
        if (cmax == c.r)
        {
            float sector = (c.g - c.b) / delta;
            // HLSL-safe modulo: wrap into [0,6)
            h = 60.0 * (sector - 6.0 * floor(sector / 6.0));
        }
        else if (cmax == c.g)
            h = 60.0 * ((c.b - c.r) / delta + 2.0);
        else
            h = 60.0 * ((c.r - c.g) / delta + 4.0);
    }
    if (h < 0.0) h += 360.0;

    float s = (cmax < 1e-6) ? 0.0 : delta / cmax;
    float v = cmax;

    return float3(h, s, v);
}

// Convert HSV → linear RGB
float3 HSVtoRGB(float3 hsv)
{
    float h = hsv.x, s = hsv.y, v = hsv.z;
    float c = v * s;
    // frac((h/60)/2)*2 gives the same result as fmod(h/60, 2) for h in [0,360]
    float hSector = h / 60.0;
    float x = c * (1.0 - abs(frac(hSector * 0.5) * 2.0 - 1.0));
    float m = v - c;

    float3 rgb;
    if      (h <  60.0) rgb = float3(c, x, 0);
    else if (h < 120.0) rgb = float3(x, c, 0);
    else if (h < 180.0) rgb = float3(0, c, x);
    else if (h < 240.0) rgb = float3(0, x, c);
    else if (h < 300.0) rgb = float3(x, 0, c);
    else                rgb = float3(c, 0, x);

    return rgb + m;
}

// Smooth step between two values — returns 0..1
float smoothFade(float val, float lo, float hi)
{
    return smoothstep(lo, hi, val) * (1.0 - smoothstep(hi, hi + (hi - lo) * 0.3, val));
}

// ─────────────────────────────────────────────
//  SKIN MASK
//  Returns 0.0 (not skin) → 1.0 (skin)
// ─────────────────────────────────────────────
float SkinMask(float3 rgb)
{
    float3 hsv = RGBtoHSV(rgb);
    float h = hsv.x; // 0..360
    float s = hsv.y; // 0..1
    float v = hsv.z; // 0..1

    // ── Hue gate ──────────────────────────────
    // Skin lives roughly in the orange/peach band.
    // We reject vivid reds (h near 0 or 360) and
    // warm browns that drift toward red (h > ~40).
    float hueLo  = SkinHueCenter - SkinHueRange;
    float hueHi  = SkinHueCenter + SkinHueRange;

    // Soft hue weight
    float hueWeight;
    float soft = max(SkinHueRange * MaskSoftness * 0.5, 0.5);
    hueWeight = smoothstep(hueLo - soft, hueLo + soft, h)
              * (1.0 - smoothstep(hueHi - soft, hueHi + soft, h));

    // ── Saturation gate ───────────────────────
    // Too grey → not skin. Too vivid → red/orange paint, not skin.
    float satWeight = smoothstep(SkinSatMin, SkinSatMin + 0.06, s)
                    * (1.0 - smoothstep(SkinSatMax - 0.06, SkinSatMax, s));

    // ── Value (brightness) gate ───────────────
    float valWeight = smoothstep(SkinValMin, SkinValMin + 0.05, v)
                    * (1.0 - smoothstep(SkinValMax - 0.05, SkinValMax, v));

    // ── Red exclusion: pure red channel bloom ─
    // Pixels where red is massively dominant and
    // green is very low are lipstick/blood/car, not skin.
    float redDominance = rgb.r - max(rgb.g, rgb.b);
    float notPureRed   = 1.0 - smoothstep(0.28, 0.45, redDominance);

    // ── Brown exclusion ───────────────────────
    // Browns have low saturation + reddish hue but also
    // very low blue. We let the hue range handle most of this.
    // Extra: if hue > 35 AND saturation > 0.45, it's likely
    // a warm brown/rust rather than skin → fade out.
    float brownPenalty = smoothstep(35.0, 45.0, h) * smoothstep(0.42, 0.55, s);
    float notBrown     = 1.0 - brownPenalty;

    return saturate(hueWeight * satWeight * valWeight * notPureRed * notBrown);
}

// ─────────────────────────────────────────────
//  MAIN PIXEL SHADER
// ─────────────────────────────────────────────
float3 PS_SkinSat(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, uv).rgb;

    float  mask  = SkinMask(color);

    // ── Apply saturation change to skin pixels ──
    float3 hsv   = RGBtoHSV(color);

    // Saturation multiplier:
    //   SaturationStrength  > 0 → boost
    //   SaturationStrength  < 0 → desaturate
    //   SaturationStrength == 0 → no change
    float  newSat;
    if (SaturationStrength >= 0.0)
        newSat = hsv.y + SaturationStrength * (1.0 - hsv.y); // boost toward 1
    else
        newSat = hsv.y * (1.0 + SaturationStrength);         // shrink toward 0

    newSat = saturate(newSat);

    // Blend original ↔ modified based on mask
    hsv.y     = lerp(hsv.y, newSat, mask);
    float3 out_color = HSVtoRGB(hsv);

    // ── Debug overlay ──────────────────────────
    if (ShowMask)
    {
        // Tint skin areas red, leave non-skin alone
        out_color = lerp(color, float3(1.0, 0.1, 0.1), mask * 0.75);
    }

    return out_color;
}

// ─────────────────────────────────────────────
//  TECHNIQUE
// ─────────────────────────────────────────────
technique SkinToneSaturation
<
    ui_label   = "Skin Tone Saturation";
    ui_tooltip = "Selectively saturate or desaturate skin tones while ignoring reds and browns.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_SkinSat;
    }
}
