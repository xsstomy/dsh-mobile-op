/**
 * Best-effort LAN discovery: probe the current /24 for the gateway's LAN
 * listener port. A TCP connect only proves that *something* is listening, so a
 * discovered host is offered as a candidate; switching to it still has to pass
 * the gateway's private-client + device-token checks.
 *
 * System API adapter: @ohos.net.socket lives here so the store stays free of it.
 */
import { socket } from '@kit.NetworkKit';

/** Concurrency cap: the socket stack and the radio dislike 254 at once. */
const DEFAULT_CONCURRENCY = 24;

export class LanScanner {
  /**
   * Resolve to the subset of `hosts` that accept a TCP connection on `port`.
   * `onProgress` receives (done, total) so the UI can show a percentage.
   */
  async scan(hosts: string[], port: number, timeoutMs: number, onProgress: (done: number, total: number) => void): Promise<string[]> {
    const found: string[] = [];
    const total = hosts.length;
    if (total === 0) {
      return found;
    }
    let next = 0;
    let done = 0;
    const worker = async (): Promise<void> => {
      while (next < total) {
        const index = next;
        next += 1;
        const host = hosts[index];
        if (await this.probe(host, port, timeoutMs)) {
          found.push(host);
        }
        done += 1;
        onProgress(done, total);
      }
    };
    const concurrency = Math.min(DEFAULT_CONCURRENCY, total);
    const workers: Promise<void>[] = [];
    for (let index = 0; index < concurrency; index += 1) {
      workers.push(worker());
    }
    for (const running of workers) {
      await running;
    }
    return found;
  }

  private async probe(host: string, port: number, timeoutMs: number): Promise<boolean> {
    let tcp: socket.TCPSocket | undefined = undefined;
    try {
      tcp = socket.constructTCPSocketInstance();
      const options: socket.TCPConnectOptions = {
        address: { address: host, port },
        timeout: timeoutMs
      };
      await tcp.connect(options);
      return true;
    } catch (error) {
      void error;
      return false;
    } finally {
      if (tcp !== undefined) {
        try {
          tcp.close();
        } catch (error) {
          void error;
        }
      }
    }
  }
}
