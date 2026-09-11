import { describe, expect, it } from '@ohos/hypium';
import {
  CompressTarget, DEFAULT_IMAGE_LIMITS, ImageLimits, PreparedImageRow, base64ByteLength, compressTarget,
  fitsImageBudget, isSupportedMediaType, mediaTypeOfName, outgoingFrameBytes, stripDataUrl
} from '../main/ets/protocol/Images';

function prepared(mediaType: string, bytes: number, base64Length: number): PreparedImageRow {
  let base64 = '';
  while (base64.length < base64Length) {
    base64 += 'A';
  }
  return { name: 'a.jpg', mediaType: mediaType, bytes: bytes, base64: base64, sourceUri: 'file://a.jpg' };
}

export default function imagesTest(): void {
  describe('images', () => {
    it('derives the media type from the file name', 0, () => {
      expect(mediaTypeOfName('IMG_1.JPG')).assertEqual('image/jpeg');
      expect(mediaTypeOfName('shot.png')).assertEqual('image/png');
      expect(mediaTypeOfName('a.webp')).assertEqual('image/webp');
      expect(mediaTypeOfName('noext')).assertEqual('image/jpeg');
      expect(isSupportedMediaType('image/bmp')).assertFalse();
      expect(isSupportedMediaType('image/png')).assertTrue();
    });

    it('computes base64 byte length for all padding cases', 0, () => {
      expect(base64ByteLength('')).assertEqual(0);
      expect(base64ByteLength('QUJD')).assertEqual(3);
      expect(base64ByteLength('QUJDRA==')).assertEqual(4);
      expect(base64ByteLength('QUJDRQ==')).assertEqual(4);
      expect(base64ByteLength('QUJDREVG')).assertEqual(6);
    });

    it('estimates the outgoing frame size', 0, () => {
      const one = prepared('image/jpeg', 1024, 1400);
      const bytes = outgoingFrameBytes([one], 'hello');
      expect(bytes > 1400).assertTrue();
      expect(bytes < 2000).assertTrue();
    });

    it('enforces the measured frame budget and per-image cap', 0, () => {
      const limits = DEFAULT_IMAGE_LIMITS;
      const small = prepared('image/jpeg', 1000, 1400);
      expect(fitsImageBudget([small], 'hi', limits)).assertTrue();
      // 3 MB raw image -> ~4 MB base64 -> above the 3.5 MB frame budget.
      const big = prepared('image/jpeg', 3 * 1024 * 1024, 4 * 1024 * 1024);
      expect(fitsImageBudget([big], 'hi', limits)).assertFalse();
      // Too many images.
      const many: PreparedImageRow[] = [];
      for (let index = 0; index < 9; index += 1) {
        many.push(small);
      }
      expect(fitsImageBudget(many, '', limits)).assertFalse();
    });

    it('downscales long edges and lowers quality for big pictures', 0, () => {
      const limits = new ImageLimits();
      const target: CompressTarget = compressTarget(6000, 4000, limits);
      expect(target.width).assertEqual(limits.maxEdge);
      expect(target.height).assertEqual(Math.round(4000 * (limits.maxEdge / 6000)));
      expect(target.quality).assertEqual(80);
      const small = compressTarget(800, 600, limits);
      expect(small.width).assertEqual(800);
      expect(small.height).assertEqual(600);
    });

    it('lowers quality before exceeding the single-image cap', 0, () => {
      const limits = new ImageLimits();
      const target = compressTarget(4000, 3000, limits);
      // 2048x1536 at q=80 is ~1.1 MB, still under the cap.
      expect(target.quality >= 40).assertTrue();
    });

    it('strips a data-url prefix', 0, () => {
      expect(stripDataUrl('data:image/png;base64,QUJD')).assertEqual('QUJD');
      expect(stripDataUrl('QUJD')).assertEqual('QUJD');
    });
  });
}
