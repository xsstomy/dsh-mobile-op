/**
 * Small platform helpers (clipboard, haptics) used by the chat surface.
 */
import pasteboard from '@ohos.pasteboard';
import vibrator from '@ohos.vibrator';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'Platform';

/** Copy plain text; returns false when the system refuses. */
export function copyToClipboard(text: string): boolean {
  if (text.length === 0) {
    return false;
  }
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setDataSync(data);
    return true;
  } catch (error) {
    hilog.warn(0x0000, TAG, 'clipboard failed: %{public}s', JSON.stringify(error));
    return false;
  }
}

/** Short haptic tick for send/receive feedback; silently ignored when unsupported. */
export function vibrateShort(): void {
  try {
    vibrator.startVibration({ type: 'time', duration: 15 }, { id: 0, usage: 'notification' }).catch((error: Error) => {
      hilog.debug(0x0000, TAG, 'vibrate skipped: %{public}s', error.message);
    });
  } catch (error) {
    hilog.debug(0x0000, TAG, 'vibrate unavailable: %{public}s', JSON.stringify(error));
  }
}
