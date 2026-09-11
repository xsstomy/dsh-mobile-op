/**
 * Default-network availability watcher (ohos.net.connection).
 *
 * The socket close/error path already schedules backoff reconnects, but a radio
 * outage can leave a dead socket whose close event never arrives (the OS may
 * withdraw it while the app is suspended). Watching the default network lets the
 * client skip the rest of the backoff and reconnect as soon as an interface is
 * usable again.
 *
 * System API adapter: the NetworkKit import lives here so the store and the pure
 * layers stay free of it.
 */
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'NetworkMonitor';

export class NetworkMonitor {
  private net: connection.NetConnection | undefined = undefined;

  /** Idempotent: watch the default network, calling onAvailable on recovery. */
  start(onAvailable: () => void): void {
    if (this.net !== undefined) {
      return;
    }
    try {
      const net = connection.createNetConnection();
      // on() must be registered before register() (module docs).
      net.on('netAvailable', (handle: connection.NetHandle) => {
        void handle;
        onAvailable();
      });
      net.register((error: BusinessError) => {
        if (error) {
          hilog.warn(0x0000, TAG, 'register failed: %{public}s', error.message);
        }
      });
      this.net = net;
    } catch (error) {
      hilog.warn(0x0000, TAG, 'start failed: %{public}s', JSON.stringify(error));
    }
  }

  stop(): void {
    const net = this.net;
    this.net = undefined;
    if (net === undefined) {
      return;
    }
    try {
      net.unregister((error: BusinessError) => {
        if (error) {
          hilog.warn(0x0000, TAG, 'unregister failed: %{public}s', error.message);
        }
      });
    } catch (error) {
      void error;
    }
  }
}
