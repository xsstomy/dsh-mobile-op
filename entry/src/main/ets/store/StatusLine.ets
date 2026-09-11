/**
 * Status-card selectors shared by the launcher (`Index`) and the workspace home
 * (`WorkspacePage`).
 *
 * Kept free of `@kit.*` (and of the gateway client) so Local Test can cover it:
 * the store snapshot type transitively imports the WebSocket kit.
 */

/**
 * Whether a status card should render its endpoint line.
 *
 * While connecting, the launcher row already shows the endpoint as its detail,
 * and once connected the raw URL is noise on either page, so both would be
 * redundant. The line is kept only when it is the single place the URL appears.
 */
export function showEndpointLine(connected: boolean, connectionDetail: string, endpoint: string): boolean {
  if (endpoint.length === 0) {
    return true;
  }
  if (connected) {
    return false;
  }
  return connectionDetail !== endpoint;
}
