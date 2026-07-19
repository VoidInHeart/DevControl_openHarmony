import { hdsEffect } from '@kit.UIDesignKit';

/**
 * HDS light feedback used by content cards on the API 24 baseline.
 * It combines a soft touch light with the system press-gradient effect.
 */
export function immersiveCardEffect(): VisualEffect {
  return new hdsEffect.HdsEffectBuilder()
    .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)
    .pointLight({
      sourceType: hdsEffect.PointLightSourceType.SOFT,
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      options: {
        color: '#C9EAFF',
        intensity: 0.72,
        height: 72,
        bloom: 0.32
      }
    })
    .buildEffect();
}
