/**
 * Continuous background task while an agent turn is running.
 *
 * Mirrors the Android client's foreground service: the socket and the agent turn
 * must survive the app moving to the background, so a `dataTransfer` continuous
 * task is started on send and stopped when the session goes idle.
 */
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'BackgroundTask';
const BUNDLE = 'com.dshmobile.app';
const ABILITY = 'EntryAbility';

export class TurnBackgroundTask {
  private running: boolean = false;
  private agent: WantAgent | undefined = undefined;

  private async buildAgent(): Promise<WantAgent | undefined> {
    if (this.agent !== undefined) {
      return this.agent;
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: BUNDLE, abilityName: ABILITY }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      this.agent = await wantAgent.getWantAgent(info);
      return this.agent;
    } catch (error) {
      hilog.warn(0x0000, TAG, 'wantAgent failed: %{public}s', JSON.stringify(error));
      return undefined;
    }
  }

  /** Idempotent: safe to call on every turn start. */
  async start(context: common.Context, label: string): Promise<void> {
    if (this.running) {
      return;
    }
    const agent = await this.buildAgent();
    if (agent === undefined) {
      return;
    }
    backgroundTaskManager.startBackgroundRunning(context,
      backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent, (error) => {
        if (error) {
          hilog.warn(0x0000, TAG, 'start continuous task failed: %{public}s', error.message);
          return;
        }
        this.running = true;
        hilog.info(0x0000, TAG, 'continuous task started (%{public}s)', label);
      });
  }

  /** Idempotent: safe to call whenever the session becomes idle. */
  stop(context: common.Context): void {
    if (!this.running) {
      return;
    }
    this.running = false;
    backgroundTaskManager.stopBackgroundRunning(context).then(() => {
      hilog.info(0x0000, TAG, 'continuous task stopped');
    }).catch((error: Error) => {
      hilog.warn(0x0000, TAG, 'stop continuous task failed: %{public}s', error.message);
    });
  }

  get isRunning(): boolean {
    return this.running;
  }
}
