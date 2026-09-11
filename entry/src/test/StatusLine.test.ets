import { describe, expect, it } from '@ohos/hypium';
import { showEndpointLine } from '../main/ets/store/StatusLine';

const URL = 'ws://192.168.3.47:3081/ws/mobile';

export default function statusLineTest(): void {
  describe('statusLine', () => {
    it('hides the endpoint line when the row already shows it', 0, () => {
      // While connecting, `connectionDetail` IS the endpoint (Index.ets statusCard).
      expect(showEndpointLine(false, URL, URL)).assertFalse();
    });

    it('hides the endpoint line once connected', 0, () => {
      expect(showEndpointLine(true, '端口 3081', URL)).assertFalse();
    });

    it('keeps the endpoint line while it is the only place the URL appears', 0, () => {
      expect(showEndpointLine(false, '已保存端点', URL)).assertTrue();
      expect(showEndpointLine(false, '第 1 次重连，2s 后', URL)).assertTrue();
      expect(showEndpointLine(false, 'upgrade failed (code=200)', URL)).assertTrue();
      expect(showEndpointLine(false, '握手完成', URL)).assertTrue();
    });

    it('shows the placeholder when no endpoint is configured', 0, () => {
      expect(showEndpointLine(false, '', '')).assertTrue();
    });
  });
}
