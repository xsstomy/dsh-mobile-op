/**
 * Design tokens ported from the upstream client design system
 * (dsh-mobile `Design/design-spec.md` + `ui/DshTheme.kt` / `ui/DshLiquidGlass.kt`).
 *
 * Only colours, typography, radii and the glass recipe are reused here. The
 * launcher icon (whale artwork) comes from the upstream AppIcon assets under
 * MIT — see NOTICE.
 *
 * Every colour is a **theme-qualified resource** (`app.color.*`, resolved from
 * `resources/base` for light and `resources/dark` for dark). ArkUI re-resolves
 * them whenever the app colour mode changes, so switching the theme repaints
 * every page immediately — plain mutable fields would stay stale because the
 * attribute closures that read them have no observed dependency (ArkUI partial
 * update).
 */

export class AppColors {
  /** Text on glass/cards. */
  static readonly DARK_INK: Resource = $r('app.color.ink');
  static readonly INK_WEAK: Resource = $r('app.color.ink_weak');
  /** Dark ink used on top of the brand/solid fills. */
  static readonly INK: Resource = $r('app.color.ink_strong');
  /** Accent text/links on the atmosphere gradient. */
  static readonly MIST: Resource = $r('app.color.mist');
  /** Text placed directly on the atmosphere gradient. */
  static readonly ON_ATMOSPHERE: Resource = $r('app.color.on_atmosphere');
  /** Text on solid brand fills (primary buttons). */
  static readonly PAPER: Resource = $r('app.color.paper');

  static readonly BRAND: Resource = $r('app.color.brand');
  static readonly OK: Resource = $r('app.color.ok');
  static readonly SUCCESS: Resource = $r('app.color.ok');
  static readonly WARN: Resource = $r('app.color.warn');
  static readonly AMBER: Resource = $r('app.color.warn');
  static readonly DANGER: Resource = $r('app.color.danger');
  static readonly PURPLE: Resource = $r('app.color.purple');
  static readonly ORANGE: Resource = $r('app.color.orange');
}

/** Frosted glass surfaces (upstream: white alpha + 0.8dp white border + blur). */
export class Glass {
  static readonly FILL: Resource = $r('app.color.glass_fill');
  static readonly FILL_STRONG: Resource = $r('app.color.glass_fill_strong');
  static readonly FILL_SUBTLE: Resource = $r('app.color.glass_fill_subtle');
  static readonly BORDER: Resource = $r('app.color.glass_border');
  static readonly BORDER_SOFT: Resource = $r('app.color.glass_border_soft');
  static readonly BORDER_WIDTH: number = 0.8;
  static readonly CODE_FILL: Resource = $r('app.color.code_fill');
  static readonly CODE_LABEL: Resource = $r('app.color.code_label');

  /**
   * Blur material must follow the current colour mode, otherwise cards turn
   * grey in light mode. `SYSTEM` resolves against the app colour mode, so the
   * material switches with the theme without any state of ours going stale.
   */
  static blurOptions(): BackgroundBlurStyleOptions {
    return { colorMode: ThemeColorMode.SYSTEM };
  }
}

/**
 * Colours that cannot be expressed as `Resource` because the consumer needs a
 * literal string: `CanvasRenderingContext2D` paint styles and the system bar
 * properties handed to `window.setWindowSystemBarProperties`.
 *
 * Kept in sync with the resource palettes by {@link applyThemeRuntime}.
 */
export class ThemeRuntime {
  /** Canvas dot-grid paint colour. */
  static gridDot: string = '#12FFFFFF';
  /** Status/navigation bar icon colour. */
  static barContent: string = '#F9FAFC';
}

/** Record the effective colour mode for the non-resource consumers above. */
export function applyThemeRuntime(dark: boolean): void {
  ThemeRuntime.gridDot = dark ? '#12FFFFFF' : '#0F2E6BE6';
  ThemeRuntime.barContent = dark ? '#F9FAFC' : '#0E131A';
}

export class AppFont {
  static readonly DISPLAY: number = 30;
  static readonly TITLE: number = 22;
  static readonly HEADING: number = 19;
  static readonly SUBTITLE: number = 16;
  static readonly BODY: number = 16;
  static readonly LABEL: number = 14;
  static readonly CAPTION: number = 12;
  static readonly MONO: number = 13.5;
}

export class AppRadius {
  static readonly NONE: number = 0;
  static readonly CARD: number = 18;
  static readonly CARD_SMALL: number = 12;
  static readonly PILL: number = 999;
  static readonly INPUT: number = 16;
  static readonly CIRCLE: number = 999;
}

export class AppSpacing {
  static readonly PAGE: number = 18;
  static readonly GAP: number = 12;
  static readonly SECTION: number = 22;
  static readonly TOUCH: number = 44;
}

export class AppShadow {
  static readonly CARD: ShadowOptions = { radius: 18, color: '#33000000', offsetX: 0, offsetY: 8 };
  static readonly SOFT: ShadowOptions = { radius: 10, color: '#26000000', offsetX: 0, offsetY: 4 };
  static readonly NONE: ShadowOptions = { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
}

/** Protocol/client limits measured in docs/spikes (OHOS frame cap, gateway contract). */
export class GatewayLimits {
  /** OHOS measured: 4 MB JSON text frame passes, 6 MB does not. */
  static readonly MAX_OUTGOING_FRAME_BYTES: number = 3.5 * 1024 * 1024;
  /** Base64 expansion is ~1.37x, so keep raw image bytes below ~2.5 MB. */
  static readonly MAX_SINGLE_IMAGE_BYTES: number = 2.5 * 1024 * 1024;
  static readonly MAX_IMAGES_PER_MESSAGE: number = 8;
  static readonly REQUEST_TIMEOUT_MS: number = 30000;
  static readonly SESSION_CREATE_TIMEOUT_MS: number = 45000;
  /** Long commands (e.g. /plan-review) run a review subagent; do not cut them at 30s. */
  static readonly COMMAND_TIMEOUT_MS: number = 900000;
  static readonly PING_INTERVAL_MS: number = 25000;
  static readonly CONNECT_TIMEOUT_MS: number = 12000;
}
