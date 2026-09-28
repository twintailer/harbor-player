#!/usr/bin/env bash
set -euo pipefail

# Same shader set and order families used by Harbor desktop. Pinning keeps the
# release deterministic even if Anime4K's main branch changes.
REV=7684e9586f8dcc738af08a1cdceb024cc184f426
BASE="https://raw.githubusercontent.com/bloc97/Anime4K/$REV/glsl"
mkdir -p Resources/Anime4K

while IFS='|' read -r source destination; do
  curl --fail --location --silent --show-error --retry 3 "$BASE/$source" --output "Resources/Anime4K/$destination"
done <<'SHADERS'
Restore/Anime4K_Clamp_Highlights.glsl|Anime4K_Clamp_Highlights.glsl
Restore/Anime4K_Restore_CNN_VL.glsl|Anime4K_Restore_CNN_VL.glsl
Restore/Anime4K_Restore_CNN_M.glsl|Anime4K_Restore_CNN_M.glsl
Restore/Anime4K_Restore_CNN_S.glsl|Anime4K_Restore_CNN_S.glsl
Restore/Anime4K_Restore_CNN_Soft_VL.glsl|Anime4K_Restore_CNN_Soft_VL.glsl
Restore/Anime4K_Restore_CNN_Soft_M.glsl|Anime4K_Restore_CNN_Soft_M.glsl
Restore/Anime4K_Restore_CNN_Soft_S.glsl|Anime4K_Restore_CNN_Soft_S.glsl
Upscale/Anime4K_Upscale_CNN_x2_VL.glsl|Anime4K_Upscale_CNN_x2_VL.glsl
Upscale/Anime4K_Upscale_CNN_x2_M.glsl|Anime4K_Upscale_CNN_x2_M.glsl
Upscale/Anime4K_Upscale_CNN_x2_S.glsl|Anime4K_Upscale_CNN_x2_S.glsl
Upscale/Anime4K_Upscale_DTD_x2.glsl|Anime4K_Upscale_DTD_x2.glsl
Upscale/Anime4K_Upscale_Original_x2.glsl|Anime4K_Upscale_Original_x2.glsl
Upscale%2BDenoise/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl|Anime4K_Upscale_Denoise_CNN_x2_VL.glsl
Upscale%2BDenoise/Anime4K_Upscale_Denoise_CNN_x2_M.glsl|Anime4K_Upscale_Denoise_CNN_x2_M.glsl
Upscale%2BDenoise/Anime4K_Upscale_Denoise_CNN_x2_S.glsl|Anime4K_Upscale_Denoise_CNN_x2_S.glsl
Upscale/Anime4K_AutoDownscalePre_x2.glsl|Anime4K_AutoDownscalePre_x2.glsl
Upscale/Anime4K_AutoDownscalePre_x4.glsl|Anime4K_AutoDownscalePre_x4.glsl
SHADERS

curl --fail --location --silent --show-error --retry 3 \
  "https://raw.githubusercontent.com/bloc97/Anime4K/$REV/LICENSE" \
  --output "Resources/Anime4K/LICENSE-Anime4K"
