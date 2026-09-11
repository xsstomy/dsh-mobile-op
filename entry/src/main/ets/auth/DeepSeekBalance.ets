/**
 * Official DeepSeek open-platform balance lookup.
 *
 * Platform adapter: the system HTTP call lives here, not in the store or the
 * pages. The URL is pinned to the official host so a key can never be sent to a
 * third party by misconfiguration.
 */
import { http } from '@kit.NetworkKit';

const BALANCE_URL = 'https://api.deepseek.com/user/balance';

/** Declared shape (ArkTS rejects untyped object literals assigned to Object). */
interface BalanceRequestHeaders {
  Authorization: string;
  Accept: string;
}

/** Raw JSON body from `GET /user/balance`; throws on a transport or HTTP error. */
export async function fetchDeepSeekBalance(apiKey: string): Promise<string> {
  const request = http.createHttp();
  const headers: BalanceRequestHeaders = {
    Authorization: `Bearer ${apiKey}`,
    Accept: 'application/json'
  };
  try {
    const response = await request.request(BALANCE_URL, {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 15000,
      readTimeout: 15000
    });
    if (response.responseCode !== 200) {
      throw new Error(`HTTP ${response.responseCode}`);
    }
    const result = response.result;
    return typeof result === 'string' ? result : '';
  } finally {
    request.destroy();
  }
}
