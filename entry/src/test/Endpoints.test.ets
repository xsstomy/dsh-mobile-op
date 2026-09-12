import { describe, expect, it } from '@ohos/hypium';
import {
  EndpointKind,
  NetworkHint,
  SavedEndpoint,
  classifyEndpoint,
  endpointKindLabel,
  hostOf,
  isPrivateIpv4,
  isSameSubnet,
  lanUrlFor,
  normalizeEndpointInput,
  parseSavedEndpoints,
  preferredEndpoint,
  serializeSavedEndpoints,
  subnetProbeHosts,
  upsertSavedEndpoint
} from '../main/ets/sync/Endpoints';

function endpoint(url: string, kind: EndpointKind, lastUsedAt: number): SavedEndpoint {
  return { url, kind, addedAt: 1, lastUsedAt };
}

function hint(privateIpv4: string, prefixLength: number): NetworkHint {
  return { available: true, privateCapable: true, privateIpv4, prefixLength };
}

export default function endpointsTest(): void {
  describe('endpoints', () => {
    it('extracts the authority host without the port', 0, () => {
      expect(hostOf('wss://gw.example.com/ws/mobile')).assertEqual('gw.example.com');
      expect(hostOf('ws://192.168.1.5:3081/ws/mobile')).assertEqual('192.168.1.5');
      expect(hostOf('ws://[fe80::1]:3081/ws/mobile')).assertEqual('fe80::1');
      expect(hostOf('not-a-url')).assertEqual('');
    });

    it('classifies public, LAN and loopback addresses', 0, () => {
      expect(classifyEndpoint('wss://gw.example.com/ws/mobile')).assertEqual('public');
      expect(classifyEndpoint('ws://192.168.1.5:3081/ws/mobile')).assertEqual('lan');
      expect(classifyEndpoint('ws://10.0.2.2:3081/ws/mobile')).assertEqual('lan');
      expect(classifyEndpoint('ws://172.16.0.4:3081/ws/mobile')).assertEqual('lan');
      expect(classifyEndpoint('ws://172.32.0.4:3081/ws/mobile')).assertEqual('public');
      expect(classifyEndpoint('ws://127.0.0.1:3080/ws/mobile')).assertEqual('local');
    });

    it('matches subnets by prefix length', 0, () => {
      expect(isPrivateIpv4('192.168.1.5')).assertTrue();
      expect(isPrivateIpv4('8.8.8.8')).assertFalse();
      expect(isSameSubnet('192.168.1.23', 24, '192.168.1.5')).assertTrue();
      expect(isSameSubnet('192.168.1.23', 24, '192.168.2.5')).assertFalse();
      expect(isSameSubnet('192.168.1.23', 16, '192.168.2.5')).assertTrue();
      expect(isSameSubnet('192.168.1.23', 32, '192.168.1.23')).assertTrue();
      expect(isSameSubnet('192.168.1.23', 32, '192.168.1.24')).assertFalse();
    });

    it('round-trips records and drops malformed rows', 0, () => {
      const list = [endpoint('wss://gw.example.com/ws/mobile', 'public', 5)];
      const restored = parseSavedEndpoints(serializeSavedEndpoints(list));
      expect(restored.length).assertEqual(1);
      expect(restored[0].url).assertEqual('wss://gw.example.com/ws/mobile');
      expect(restored[0].kind).assertEqual('public');
      expect(parseSavedEndpoints('not json').length).assertEqual(0);
      expect(parseSavedEndpoints('[{"url":"nonsense"}]').length).assertEqual(0);
    });

    it('deduplicates on upsert and keeps the newest first', 0, () => {
      let list: SavedEndpoint[] = [];
      list = upsertSavedEndpoint(list, 'wss://gw.example.com/ws/mobile', 10, 8);
      list = upsertSavedEndpoint(list, 'ws://192.168.1.5:3081/ws/mobile', 20, 8);
      list = upsertSavedEndpoint(list, 'wss://gw.example.com/ws/mobile', 30, 8);
      expect(list.length).assertEqual(2);
      expect(list[0].url).assertEqual('wss://gw.example.com/ws/mobile');
      expect(list[0].addedAt).assertEqual(10);
      expect(list[0].lastUsedAt).assertEqual(30);
      expect(list[1].url).assertEqual('ws://192.168.1.5:3081/ws/mobile');
    });

    it('prefers a same-subnet LAN address over a newer public one', 0, () => {
      const list = [
        endpoint('wss://gw.example.com/ws/mobile', 'public', 100),
        endpoint('ws://192.168.1.5:3081/ws/mobile', 'lan', 50)
      ];
      expect(preferredEndpoint(list, hint('192.168.1.23', 24)))
        .assertEqual('ws://192.168.1.5:3081/ws/mobile');
      expect(preferredEndpoint(list, hint('192.168.2.23', 24)))
        .assertEqual('wss://gw.example.com/ws/mobile');
      expect(preferredEndpoint(list, { available: false, privateCapable: false, privateIpv4: '', prefixLength: 0 }))
        .assertEqual('wss://gw.example.com/ws/mobile');
      expect(preferredEndpoint([], hint('192.168.1.23', 24))).assertEqual('');
    });

    it('builds a bounded probe list for the current /24', 0, () => {
      const hosts = subnetProbeHosts('192.168.1.23', 24, 254);
      expect(hosts.length).assertEqual(253);
      expect(hosts.indexOf('192.168.1.23')).assertEqual(-1);
      expect(hosts.indexOf('192.168.1.5') >= 0).assertTrue();
      expect(hosts.indexOf('192.168.1.254') >= 0).assertTrue();
      expect(subnetProbeHosts('192.168.1.23', 16, 10).length).assertEqual(10);
      expect(subnetProbeHosts('nope', 24, 254).length).assertEqual(0);
      expect(lanUrlFor('192.168.1.5')).assertEqual('ws://192.168.1.5:3081/ws/mobile');
    });

    it('normalizes user input into a LAN websocket URL', 0, () => {
      expect(normalizeEndpointInput('192.168.1.5'))
        .assertEqual('ws://192.168.1.5:3081/ws/mobile');
      expect(normalizeEndpointInput(' 192.168.1.5:9000 '))
        .assertEqual('ws://192.168.1.5:9000/ws/mobile');
      expect(normalizeEndpointInput('wss://gw.example.com/ws/mobile'))
        .assertEqual('wss://gw.example.com/ws/mobile');
      expect(normalizeEndpointInput('')).assertEqual('');
      expect(endpointKindLabel(classifyEndpoint('ws://10.0.2.2:3081/ws/mobile'))).assertEqual('局域网');
    });
  });
}
