import { describe, expect, it } from '@ohos/hypium';
import { QueueRow, canSteer, placementLabel, queueImageCount, queueTextOf, toQueueRows } from '../main/ets/protocol/Queue';
import { WireQueueItem } from '../main/ets/protocol/Types';

class TextPart {
  type: string = 'text';
  text: string;

  constructor(text: string) {
    this.text = text;
  }
}

class AttachmentRef {
  attachmentId: string;

  constructor(attachmentId: string) {
    this.attachmentId = attachmentId;
  }
}

class ImagePart {
  type: string = 'image';
  attachment: AttachmentRef;

  constructor(attachmentId: string) {
    this.attachment = new AttachmentRef(attachmentId);
  }
}

class HostMessage {
  id: string;
  content: Object[];

  constructor(id: string, content: Object[]) {
    this.id = id;
    this.content = content;
  }
}

function item(id: string, placement: string, parts: Object[]): WireQueueItem {
  return new QueueItemFixture(id, placement, new HostMessage(`${id}-msg`, parts));
}

class QueueItemFixture implements WireQueueItem {
  id: string;
  placement: string;
  message: Object;

  constructor(id: string, placement: string, message: Object) {
    this.id = id;
    this.placement = placement;
    this.message = message;
  }
}

export default function queueTest(): void {
  describe('queue', () => {
    it('extracts queued text from content parts', 0, () => {
      const queued = item('m1', 'queued', [new TextPart('稍后处理')]);
      expect(queueTextOf(queued)).assertEqual('稍后处理');
      expect(queueImageCount(queued)).assertEqual(0);
    });

    it('counts images and joins multiple text parts', 0, () => {
      const queued = item('m2', 'queued', [
        new TextPart('看图 '),
        new ImagePart('a1'),
        new TextPart('并回答')
      ]);
      expect(queueTextOf(queued)).assertEqual('看图 并回答');
      expect(queueImageCount(queued)).assertEqual(1);
    });

    it('maps wire items into rows and labels placements', 0, () => {
      const rows: QueueRow[] = toQueueRows([
        item('m1', 'queued', [new TextPart('a')]),
        item('m2', 'steering', [new TextPart('b')]),
        item('m3', 'context', [])
      ]);
      expect(rows.length).assertEqual(3);
      expect(rows[0].itemId).assertEqual('m1');
      expect(placementLabel(rows[0].placement)).assertEqual('下一回合');
      expect(placementLabel(rows[1].placement)).assertEqual('插入当前回合');
      expect(placementLabel('unknown')).assertEqual('unknown');
    });

    it('only allows steering a queued item while the session runs', 0, () => {
      const queued = item('m1', 'queued', [new TextPart('a')]);
      const steering = item('m2', 'steering', [new TextPart('b')]);
      expect(canSteer(toQueueRows([queued])[0], true)).assertTrue();
      expect(canSteer(toQueueRows([queued])[0], false)).assertFalse();
      expect(canSteer(toQueueRows([steering])[0], true)).assertFalse();
    });

    it('tolerates malformed items', 0, () => {
      const broken: WireQueueItem = new QueueItemFixture('m9', '', new HostMessage('x', []));
      expect(queueTextOf(broken)).assertEqual('');
      expect(queueImageCount(broken)).assertEqual(0);
      expect(toQueueRows([broken])[0].placement).assertEqual('queued');
    });
  });
}
