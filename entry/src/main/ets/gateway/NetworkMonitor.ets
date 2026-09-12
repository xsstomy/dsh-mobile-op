/**
 * Default-network watcher + network snapshot (ohos.net.connection).
 *
 * The socket close/error path already schedules backoff reconnects, but a radio
 * outage can leave a dead socket whose close event never arrives (the OS may
 * withdraw it while the app is suspended). Watching the default network lets the
 * client skip the rest of the backoff and reconnect as soon as an interface is
 * usable again.
 *
 * The same watcher also feeds the endpoint chooser: `hint()` reports whether the
 * default network can carry a private source address and what that address is,
 * so a saved LAN endpoint can be preferred at home and a public one elsewhere.
 *
 * System API adapter: the NetworkKit import lives here so the store and the pure
 * layers stay free of it.
 */
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NetworkHint, emptyNetworkHint, isIpv4, isPrivateIpv4 } from '../sync/Endpoints';

const TAG = 'NetworkMonitor';

export class NetworkMonitor {
  private net: connection.NetConnection | undefined = undefined;

  /**
   * Idempotent: watch the default network. `onAvailable` fires when a usable
   * interface appears (skip reconnect backoff); `onChanged` fires on any
   * capability/property change (re-evaluate the preferred endpoint). All four
   * events are registered because a Wi-Fi→cellular move can arrive as either a
   * capability change or a properties change depending on the vendor build.
   */
  start(onAvailable: () => void, onChanged: () => void): void {
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
      net.on('netLost', (handle: connection.NetHandle) => {
        void handle;
        onChanged();
      });
      net.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
        void info;
        onChanged();
      });
      net.on('netConnectionPropertiesChange', (info: connection.NetConnectionPropertyInfo) => {
        void info;
        onChanged();
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

  /**
   * Best-effort snapshot of the default network. A denied permission or an
   * unsupported call yields "no private address", which safely falls back to the
   * public endpoint instead of guessing.
   */
  hint(): NetworkHint {
    try {
      const handle = connection.getDefaultNetSync();
      if (handle.netId === 0) {
        return emptyNetworkHint();
      }
      const capabilities = connection.getNetCapabilitiesSync(handle);
      let privateCapable = false;
      for (const bearer of capabilities.bearerTypes) {
        if (bearer === connection.NetBearType.BEARER_WIFI || bearer === connection.NetBearType.BEARER_ETHERNET) {
          privateCapable = true;
        }
      }
      const properties = connection.getConnectionPropertiesSync(handle);
      let privateIpv4 = '';
      let prefixLength = 24;
      for (const link of properties.linkAddresses) {
        const value = link.address.address;
        if (!isIpv4(value) || !isPrivateIpv4(value)) {
          continue;
        }
        privateIpv4 = value;
        prefixLength = link.prefixLength;
        break;
      }
      return { available: true, privateCapable, privateIpv4, prefixLength };
    } catch (error) {
      hilog.debug(0x0000, TAG, 'hint unavailable: %{public}s', JSON.stringify(error));
      return emptyNetworkHint();
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
