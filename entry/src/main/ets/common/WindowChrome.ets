/**
 * Immersive window chrome: the app draws the atmosphere edge to edge and the
 * system bars become transparent, so no white band is left above the status bar
 * or below the navigation bar.
 *
 * `setWindowLayoutFullScreen(true)` hands the whole window to the page, so the
 * avoid areas are published as `gwInsetTop` / `gwInsetBottom` (vp) for the page
 * content to pad against — the documented pattern for immersive layouts.
 *
 * Kept out of the pages so both the ability (startup, configuration change) and
 * the store (theme switch) can refresh it with one call.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeRuntime } from './Constants';

const TAG = 'WindowChrome';
export const INSET_TOP_KEY = 'gwInsetTop';
export const INSET_BOTTOM_KEY = 'gwInsetBottom';

export class WindowChrome {
  private static main: window.Window | undefined = undefined;

  /** Remember the main window once so later refreshes need no stage handle. */
  static attach(windowStage: window.WindowStage): void {
    try {
      WindowChrome.main = windowStage.getMainWindowSync();
    } catch (error) {
      hilog.error(0x0000, TAG, 'getMainWindowSync failed: %{public}s', JSON.stringify(error));
      return;
    }
    WindowChrome.apply();
  }

  /** Full-screen layout + transparent bars whose icons follow the theme. */
  static apply(): void {
    const main = WindowChrome.main;
    if (main === undefined) {
      return;
    }
    main.setWindowLayoutFullScreen(true).catch((error: Error) => {
      hilog.error(0x0000, TAG, 'setWindowLayoutFullScreen failed: %{public}s', error.message);
    });
    const properties: window.SystemBarProperties = {
      statusBarColor: '#00000000',
      statusBarContentColor: ThemeRuntime.barContent,
      navigationBarColor: '#00000000',
      navigationBarContentColor: ThemeRuntime.barContent
    };
    main.setWindowSystemBarProperties(properties).catch((error: Error) => {
      hilog.error(0x0000, TAG, 'setWindowSystemBarProperties failed: %{public}s', error.message);
    });
  }

  /**
   * Status/navigation bar heights in vp, for the page content to pad against.
   * Must run after the window is created (before `loadContent` completes the
   * window reports `1300002`), and again whenever the configuration changes.
   */
  static publishInsets(): void {
    const main = WindowChrome.main;
    if (main === undefined) {
      return;
    }
    try {
      const avoid = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const ui = main.getUIContext();
      const top = ui.px2vp(avoid.topRect.height);
      let bottom = ui.px2vp(avoid.bottomRect.height);
      if (bottom <= 0) {
        // Gesture navigation reports its bar outside TYPE_SYSTEM on some builds.
        for (const kind of [window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR, window.AvoidAreaType.TYPE_SYSTEM_GESTURE]) {
          const candidate = ui.px2vp(main.getWindowAvoidArea(kind).bottomRect.height);
          if (candidate > bottom) {
            bottom = candidate;
          }
        }
      }
      AppStorage.setOrCreate<number>(INSET_TOP_KEY, top);
      AppStorage.setOrCreate<number>(INSET_BOTTOM_KEY, bottom);
    } catch (error) {
      hilog.error(0x0000, TAG, 'avoid area failed: %{public}s', JSON.stringify(error));
    }
  }
}
