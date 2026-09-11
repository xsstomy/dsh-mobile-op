/**
 * Turn activity (pure logic, unit tested).
 *
 * The conversation projection alone cannot answer "is the agent working right
 * now?": a turn can be running before any bubble exists (the host may answer
 * with a single `assistant/message`), and the send-request `busy` flag is
 * already false once the gateway acks the `message` request. The store therefore
 * keeps this one small state machine, fed by live events, by a successful send
 * and by the host's own `session.running` truth (which also survives a
 * reconnect).
 */

export interface TurnActivityState {
  active: boolean;
  /** Epoch ms the turn started; 0 = running but the start is unknown. */
  startedAt: number;
}

export function turnIdle(): TurnActivityState {
  return { active: false, startedAt: 0 };
}

/** Running state; `startedAt <= 0` means "in flight, start unknown". */
export function turnRunning(startedAt: number): TurnActivityState {
  return { active: true, startedAt: startedAt > 0 ? startedAt : 0 };
}

/**
 * Fold one live event into the state. `eventTime` is the wire `time` (epoch ms)
 * and is preferred over the local clock so a replayed frame keeps its own
 * timeline; `<= 0` falls back to `now`.
 */
export function applyTurnActivity(state: TurnActivityState, eventType: string, eventTime: number, now: number): TurnActivityState {
  const time = eventTime > 0 ? eventTime : now;
  switch (eventType) {
    case 'turn/start':
      return { active: true, startedAt: time };
    case 'user/message':
      // Covers steering/queued turns and the window where the send succeeded but
      // `turn/start` has not arrived yet: keep the first known start time.
      return state.active ? state : { active: true, startedAt: time };
    case 'turn/end':
    case 'agent/error':
    case 'session/error':
      return turnIdle();
    default:
      return state;
  }
}
