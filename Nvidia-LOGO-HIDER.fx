/*
╔══════════════════════════════════════════════════════════════════════╗
║           Nvidia-LOGO-HIDER.fx — Linked Area Copy                       ║
║  One box to position. Source region auto-mirrors it, offset above.  ║
║  Size and placement always in sync — copy fits right away.          ║
╚══════════════════════════════════════════════════════════════════════╝

  QUICK START:
  1. Drop into <Game>\reshade-shaders\Shaders\  and enable in ReShade
  2. Turn ON "Show Debug Outlines"
       RED  box = destination (covers subtitle)
       GREEN box = source (background being copied — auto-linked)
  3. Drag BoxCenterX / BoxCenterY until RED box sits over the subtitle
  4. Adjust BoxWidth / BoxHeight to fit the subtitle exactly
  5. Drag SourceOffsetY up (increase) until GREEN box clears any HUD
  6. Fine-tune Feather, Brightness, Contrast until seamless
  7. Turn OFF "Show Debug Outlines"

  SOURCE IS ALWAYS THE SAME SIZE AS THE DESTINATION — no manual sizing.
*/

#include "ReShade.fxh"

// ─────────────────────────────────────────────────────────────────────────────
//  DESTINATION BOX — place this over your subtitle
// ─────────────────────────────────────────────────────────────────────────────

uniform float BoxCenterX <
    ui_type     = "slider";
    ui_label    = "Position X";
    ui_tooltip  = "Horizontal center of the subtitle cover area.\n"
                  "0.0 = left edge, 1.0 = right edge.";
    ui_category = "1. Position & Size";
    ui_min      = 0.0;
    ui_max      = 1.0;
    ui_step     = 0.001;
> = 0.82;

uniform float BoxCenterY <
    ui_type     = "slider";
    ui_label    = "Position Y";
    ui_tooltip  = "Vertical center of the subtitle cover area.\n"
                  "0.0 = top, 1.0 = bottom of screen.";
    ui_category = "1. Position & Size";
    ui_min      = 0.0;
    ui_max      = 1.0;
    ui_step     = 0.001;
> = 0.88;

uniform float BoxWidth <
    ui_type     = "slider";
    ui_label    = "Width";
    ui_tooltip  = "Width of the cover area. Source copy automatically matches this.";
    ui_category = "1. Position & Size";
    ui_min      = 0.01;
    ui_max      = 1.0;
    ui_step     = 0.005;
> = 0.32;

uniform float BoxHeight <
    ui_type     = "slider";
    ui_label    = "Height";
    ui_tooltip  = "Height of the cover area. Source copy automatically matches this.";
    ui_category = "1. Position & Size";
    ui_min      = 0.005;
    ui_max      = 0.4;
    ui_step     = 0.002;
> = 0.07;

// ─────────────────────────────────────────────────────────────────────────────
//  SOURCE OFFSET — how far above the destination to copy from
// ─────────────────────────────────────────────────────────────────────────────

uniform float SourceOffsetY <
    ui_type     = "slider";
    ui_label    = "Source Offset (above)";
    ui_tooltip  = "How far ABOVE the subtitle to copy the background from.\n"
                  "Increase this until the GREEN box clears any HUD elements.\n"
                  "Source is always the same size as the destination.";
    ui_category = "2. Source";
    ui_min      = 0.01;
    ui_max      = 0.5;
    ui_step     = 0.001;
> = 0.08;

uniform float SourceOffsetX <
    ui_type     = "slider";
    ui_label    = "Source Offset X (horizontal shift)";
    ui_tooltip  = "Shift the source region left or right relative to the destination.\n"
                  "0.0 = directly above. Useful when background varies horizontally.";
    ui_category = "2. Source";
    ui_min      = -0.5;
    ui_max      = 0.5;
    ui_step     = 0.001;
> = 0.0;

// ─────────────────────────────────────────────────────────────────────────────
//  BLEND & ADJUSTMENTS
// ─────────────────────────────────────────────────────────────────────────────

uniform float BlendFeather <
    ui_type     = "slider";
    ui_label    = "Edge Feather";
    ui_tooltip  = "Softness of the copy edges. Increase until the box border disappears.";
    ui_category = "3. Blend & Adjustments";
    ui_min      = 0.0;
    ui_max      = 1.05;
    ui_step     = 0.0005;
> = 0.010;

uniform float Brightness <
    ui_type     = "slider";
    ui_label    = "Brightness";
    ui_tooltip  = "Brighten or darken the copied patch to match surrounding lighting.\n"
                  "1.0 = unchanged.";
    ui_category = "3. Blend & Adjustments";
    ui_min      = 0.0;
    ui_max      = 3.0;
    ui_step     = 0.01;
> = 1.0;

uniform float Contrast <
    ui_type     = "slider";
    ui_label    = "Contrast";
    ui_tooltip  = "Adjust contrast of the copied patch.\n"
                  "1.0 = unchanged. Lower to flatten, raise to punch up.";
    ui_category = "3. Blend & Adjustments";
    ui_min      = 0.0;
    ui_max      = 4.0;
    ui_step     = 0.01;
> = 1.0;

// ─────────────────────────────────────────────────────────────────────────────
//  DEBUG
// ─────────────────────────────────────────────────────────────────────────────

uniform bool ShowDebug <
    ui_type     = "checkbox";
    ui_label    = "Show Debug Outlines";
    ui_tooltip  = "RED = destination (subtitle cover area).\n"
                  "GREEN = source (background being copied).\n"
                  "Both are always the same size. Disable when done.";
    ui_category = "4. Debug";
> = false;

// ─────────────────────────────────────────────────────────────────────────────
//  SAMPLER
// ─────────────────────────────────────────────────────────────────────────────

sampler BackBuffer
{
    Texture   = ReShade::BackBufferTex;
    AddressU  = CLAMP;
    AddressV  = CLAMP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

// ─────────────────────────────────────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────────────────────────────────────

float BoxMask(float2 uv, float cx, float cy, float hw, float hh, float feather)
{
    float f  = max(feather, 0.0001);
    float mL = smoothstep(0.0, f, uv.x - (cx - hw));
    float mR = smoothstep(0.0, f, (cx + hw) - uv.x);
    float mT = smoothstep(0.0, f, uv.y - (cy - hh));
    float mB = smoothstep(0.0, f, (cy + hh) - uv.y);
    return mL * mR * mT * mB;
}

float BoxOutline(float2 uv, float cx, float cy, float hw, float hh, float t)
{
    float outer = BoxMask(uv, cx, cy, hw + t, hh + t, 0.001);
    float inner = BoxMask(uv, cx, cy, max(hw - t, 0.0), max(hh - t, 0.0), 0.001);
    return saturate(outer - inner);
}

float3 AdjustColor(float3 col, float brightness, float contrast)
{
    col = (col - 0.5) * contrast + 0.5;
    col *= brightness;
    return saturate(col);
}

// ─────────────────────────────────────────────────────────────────────────────
//  MAIN PIXEL SHADER
// ─────────────────────────────────────────────────────────────────────────────

float4 PS_SubtitleHider(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 original = tex2D(BackBuffer, uv).rgb;

    // Half-extents — destination and source are always the same size
    float hw = clamp(BoxWidth  * 0.5, 0.001, 0.75);
    float hh = clamp(BoxHeight * 0.5, 0.001, 0.35);

    // Destination center
    float dCX = BoxCenterX;
    float dCY = BoxCenterY;

    // Source center — same size, offset above (and optionally sideways)
    float sCX = BoxCenterX + SourceOffsetX;
    float sCY = BoxCenterY - BoxHeight - SourceOffsetY;

    // Feather capped so it never exceeds the smallest dimension
    float feather = min(BlendFeather, min(hw, hh) * 0.49);

    // Destination mask for this pixel
    float mask = BoxMask(uv, dCX, dCY, hw, hh, feather);

    float3 result = original;

    if (mask > 0.0)
    {
        // ── Remap pixel from destination space → source space ─────────────────
        //
        //  The destination and source boxes are the same size, so the mapping
        //  is a pure translation — no scaling needed. We just compute how far
        //  this pixel is from the destination center, then add that offset to
        //  the source center. The copy lands pixel-perfect with no stretching.
        //
        float2 delta  = uv - float2(dCX, dCY);           // offset from dst center
        float2 srcUV  = float2(sCX, sCY) + delta;         // same offset in src space
        srcUV         = clamp(srcUV, 0.001, 0.999);

        float3 copied = tex2D(BackBuffer, srcUV).rgb;
        copied        = AdjustColor(copied, Brightness, Contrast);

        result = lerp(original, copied, mask);
    }

    // ── Debug outlines ────────────────────────────────────────────────────────
    if (ShowDebug)
    {
        float sCY_clamped = clamp(sCY, 0.001, 0.999);

        float dstLine = BoxOutline(uv, dCX, dCY, hw, hh, 0.003);
        result = lerp(result, float3(1.0, 0.08, 0.05), dstLine);

        float srcLine = BoxOutline(uv, sCX, sCY_clamped, hw, hh, 0.003);
        result = lerp(result, float3(0.08, 1.0, 0.12), srcLine);
    }

    return float4(result, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
//  TECHNIQUE
// ─────────────────────────────────────────────────────────────────────────────

technique Nvidia-LOGO-HIDER
<
    ui_label   = "Nvidia-LOGO-HIDER";
    ui_tooltip = "Position one box over the subtitle.\n"
                 "Background is auto-copied from the same-sized region above it.\n"
                 "RED = destination, GREEN = source (always linked in size).";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_SubtitleHider;
    }
}
