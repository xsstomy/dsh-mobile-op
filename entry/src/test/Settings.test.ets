import { describe, expect, it } from '@ohos/hypium';
import {
  agentPresetsFrom, commandGroupsFrom, currentModelFrom, currentPermissionFrom, effortsFor, filterCommands,
  modelGroupsFrom, modelRowFor, permissionOptionsFrom, slashQueryOf
} from '../main/ets/protocol/Settings';
import {
  AGENT_PRESETS_FRAME, COMMANDS_FRAME, DEFAULT_MODEL_FRAME, DEFAULTS_FRAME, MODELS_FRAME, PERMISSION_OPTIONS_FRAME
} from './fixtures/Frames';
import { decodeFrame } from '../main/ets/protocol/WireDecoder';

export default function settingsTest(): void {
  describe('settings', () => {
    it('flattens the model catalogue and never flags two models at once', 0, () => {
      const frame = decodeFrame(MODELS_FRAME)!;
      const groups = modelGroupsFrom(frame);
      expect(groups.length > 0).assertTrue();
      expect(groups[0].models.length > 0).assertTrue();
      const current = currentModelFrom(frame);
      expect(current.provider.length > 0).assertTrue();
      let selected = 0;
      for (const group of groups) {
        for (const model of group.models) {
          if (model.selected) {
            selected += 1;
          }
        }
      }
      // The live provider may not be part of the catalogue groups, then 0 is correct.
      expect(selected <= 1).assertTrue();
    });

    it('marks exactly the current model when it is in the catalogue', 0, () => {
      const synthetic = '{"kind":"models","current":{"provider":"p1","model":"m2"},' +
        '"routable":true,"groups":[{"id":"p1","name":"P1","models":[{"id":"m1","name":"M1"},' +
        '{"id":"m2","name":"M2"}]}]}';
      const groups = modelGroupsFrom(decodeFrame(synthetic)!);
      expect(groups.length).assertEqual(1);
      expect(groups[0].models[0].selected).assertFalse();
      expect(groups[0].models[1].selected).assertTrue();
    });

    it('returns reasoning efforts with the active one last', 0, () => {
      const groups = modelGroupsFrom(decodeFrame(MODELS_FRAME)!);
      let groupId = '';
      let modelId = '';
      let defaultEffort = '';
      let effortCount = 0;
      for (const group of groups) {
        for (const model of group.models) {
          if (model.efforts.length > 0) {
            groupId = group.id;
            modelId = model.id;
            defaultEffort = model.defaultEffort;
            effortCount = model.efforts.length;
          }
        }
      }
      expect(effortCount > 0).assertTrue();
      const ordered = effortsFor(groups, groupId, modelId, defaultEffort);
      expect(ordered.length).assertEqual(effortCount);
      expect(ordered[ordered.length - 1].id).assertEqual(defaultEffort);
      expect(effortsFor(groups, 'no-such-provider', modelId, '').length).assertEqual(0);
    });

    it('resolves a session route by provider AND model, never by id alone', 0, () => {
      // Mirrors the live host: the same model id (m1) appears under a live
      // routing provider with no reasoning levels and under its declared
      // provider with them. Only the (provider, model) pair may resolve.
      const synthetic = '{"kind":"models","current":{"provider":"live","model":"m1"},' +
        '"routable":true,"groups":[' +
        '{"id":"live","name":"live","models":[{"id":"m1","name":"m1"}]},' +
        '{"id":"declared","name":"Declared","models":[{"id":"m1","name":"M1",' +
        '"reasoning":{"efforts":[{"id":"high","name":"High"}],"defaultEffort":"high"}}]}]}';
      const groups = modelGroupsFrom(decodeFrame(synthetic)!);
      const live = modelRowFor(groups, 'live', 'm1');
      expect(live !== undefined).assertTrue();
      if (live !== undefined) {
        expect(live.name).assertEqual('m1');
        expect(live.efforts.length).assertEqual(0);
        expect(live.defaultEffort.length).assertEqual(0);
      }
      const declared = modelRowFor(groups, 'declared', 'm1');
      expect(declared !== undefined).assertTrue();
      if (declared !== undefined) {
        expect(declared.efforts.length).assertEqual(1);
        expect(declared.efforts[0].id).assertEqual('high');
      }
      // Missing model / missing provider must not silently borrow the other
      // route's efforts - that is what made the picker look broken.
      expect(modelRowFor(groups, 'live', 'no-such-model') === undefined).assertTrue();
      expect(modelRowFor(groups, 'no-such-provider', 'm1') === undefined).assertTrue();
    });

    it('reads permission presets from the real {value,name,currentValue} shape', 0, () => {
      const frame = decodeFrame(PERMISSION_OPTIONS_FRAME)!;
      const options = permissionOptionsFrom(frame);
      expect(options.length > 0).assertTrue();
      const current = currentPermissionFrom(frame);
      expect(current.length > 0).assertTrue();
      let selected = 0;
      for (const option of options) {
        if (option.selected) {
          selected += 1;
        }
      }
      expect(selected).assertEqual(1);
    });

    it('reads agent presets and the default marker', 0, () => {
      const frame = decodeFrame(AGENT_PRESETS_FRAME)!;
      const presets = agentPresetsFrom(frame);
      expect(presets.length > 0).assertTrue();
      let defaults = 0;
      for (const preset of presets) {
        if (preset.isDefault) {
          defaults += 1;
        }
      }
      expect(defaults).assertEqual(1);
      expect(presets[0].name.length > 0).assertTrue();
    });

    it('reads deployment defaults and the default model selection', 0, () => {
      const defaults = decodeFrame(DEFAULTS_FRAME)!;
      expect((defaults.agentPresetDefault ?? '').length > 0).assertTrue();
      expect((defaults.permissionDefault ?? '').length > 0).assertTrue();
      const selection = decodeFrame(DEFAULT_MODEL_FRAME)!.selection;
      expect(selection !== undefined).assertTrue();
      expect((selection?.provider ?? '').length > 0).assertTrue();
    });

    it('builds the slash command catalogue with ui instructions', 0, () => {
      const frame = decodeFrame(COMMANDS_FRAME)!;
      const groups = commandGroupsFrom(frame);
      expect(groups.length > 0).assertTrue();
      const first = groups[0];
      expect(first.title.length > 0).assertTrue();
      expect(first.items.length > 0).assertTrue();
      expect(first.items[0].name.length > 0).assertTrue();
      expect(first.items[0].kind.length > 0).assertTrue();
    });

    it('filters commands by the typed token', 0, () => {
      const groups = commandGroupsFrom(decodeFrame(COMMANDS_FRAME)!);
      const first = groups[0].items[0].name;
      const filtered = filterCommands(groups, first.substring(0, 3));
      expect(filtered.length > 0).assertTrue();
      expect(filtered[0].items[0].name.startsWith(first.substring(0, 3))).assertTrue();
      expect(filterCommands(groups, 'zzz-not-a-command').length).assertEqual(0);
    });

    it('detects when the composer should show the slash menu', 0, () => {
      expect(slashQueryOf('/')).assertEqual('');
      expect(slashQueryOf('/com')).assertEqual('com');
      expect(slashQueryOf('/compact now')).assertNull();
      expect(slashQueryOf('hello')).assertNull();
      expect(slashQueryOf('hi /com')).assertNull();
    });
  });
}
