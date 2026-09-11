/**
 * Settings: appearance, current-session switches (agent preset / model /
 * permission), deployment defaults (agent preset / default model / default
 * permission) and un-pairing.
 *
 * ArkUI only re-runs an attribute closure when it read an observed value while
 * executing, so every builder here that renders a *selected* state reads
 * `this.ui` itself instead of receiving the value as a @Builder parameter — a
 * by-value parameter would never refresh after `publish()`.
 */
import { KeyboardAvoidMode, router } from '@kit.ArkUI';
import { GatewayStore } from '../store/GatewayStore';
import { UI_KEY, UiSnapshot, emptyUiSnapshot, activeWorkspace, sessionPresetId, agentPresetLabel } from '../store/UiState';
import { AppColors, AppFont, AppRadius, AppSpacing, AppShadow, Glass } from '../common/Constants';
import {
  AgentPresetRow, ModelGroupRow, ModelRow, PermissionOptionRow, permissionLabel
} from '../protocol/Settings';
import { HarnessBackground } from '../common/HarnessBackground';

@Entry
@Component
struct SettingsPage {
  @StorageLink(UI_KEY) ui: UiSnapshot = emptyUiSnapshot();
  /** Status/navigation bar insets (vp) published by WindowChrome. */
  @StorageProp('gwInsetTop') insetTop: number = 0;
  @StorageProp('gwInsetBottom') insetBottom: number = 0;
  @State error: string = '';
  @State notice: string = '';
  @State confirmUnpair: boolean = false;
  /** Expanded group inside the deployment-defaults card ('' = all collapsed). */
  @State openSection: string = '';
  /** Expanded picker inside the current-session card ('' = none). */
  @State sessionSection: string = '';
  private store: GatewayStore = GatewayStore.current;

  async aboutToAppear(): Promise<void> {
    // Compress the page instead of lifting it, so the composer/inputs stay put.
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    try {
      await this.store.refreshSettings();
      if (this.ui.activeSessionId.length > 0) {
        await this.store.refreshModels(this.ui.activeSessionId);
        await this.store.refreshPermissions(this.ui.activeSessionId);
      }
    } catch (failure) {
      this.error = (failure as Error).message;
    }
  }

  private async run(action: () => Promise<void>): Promise<void> {
    this.error = '';
    this.notice = '';
    try {
      await action();
      this.notice = '已更新';
    } catch (failure) {
      // Surface host refusals right where the user tapped; the inline text below
      // is often scrolled out of view.
      this.error = (failure as Error).message;
      this.toast(this.error);
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 4000 });
    } catch (error) {
      void error;
    }
  }

  // ---- derived labels (read this.ui so their callers refresh) -------------

  /** Agent preset of the session currently open in the conversation page. */
  private sessionPresetId(): string {
    return sessionPresetId(this.ui);
  }

  /** Preset display name (e.g. `ptc` → `PTC 模式`), like the DSH header label. */
  private presetLabel(id: string): string {
    const label = agentPresetLabel(this.ui, id);
    return label.length > 0 ? label : '未同步';
  }

  /** Model display name from the catalogue; falls back to the raw id. */
  private modelLabelOf(provider: string, model: string): string {
    if (model.length === 0) {
      return '未同步';
    }
    for (const group of this.ui.modelGroups) {
      if (provider.length > 0 && group.id !== provider) {
        continue;
      }
      for (const entry of group.models) {
        if (entry.id === model) {
          return entry.name;
        }
      }
    }
    return model;
  }

  private sessionModelLabel(): string {
    const current = this.ui.currentModel;
    return this.modelLabelOf(current.provider, current.model);
  }

  private sessionPermissionLabel(): string {
    const current = this.ui.currentPermission;
    if (current.length > 0) {
      return permissionLabel(current);
    }
    for (const option of this.ui.permissionOptions) {
      if (option.selected) {
        return permissionLabel(option.value);
      }
    }
    return '未同步';
  }

  private presetOptionSelected(id: string): boolean {
    return id === (this.ui.defaults?.agentPresetDefault ?? '');
  }

  private defaultModelSelected(groupId: string, modelId: string): boolean {
    const selected = this.ui.defaultModel;
    if (selected === null) {
      return false;
    }
    return selected.provider === groupId && selected.model === modelId;
  }

  private defaultPermissionSelected(value: string): boolean {
    return value === (this.ui.defaults?.permissionDefault ?? '');
  }

  private sessionModelSelected(groupId: string, modelId: string): boolean {
    const current = this.ui.currentModel;
    return current.provider === groupId && current.model === modelId;
  }

  private sessionPermissionSelected(value: string): boolean {
    if (this.ui.currentPermission.length > 0) {
      return this.ui.currentPermission === value;
    }
    for (const option of this.ui.permissionOptions) {
      if (option.value === value) {
        return option.selected;
      }
    }
    return false;
  }

  // ---- builders ----------------------------------------------------------

  /** Header value for a deployment-defaults group, read lazily from this.ui. */
  private sectionValue(key: string): string {
    if (key === 'preset') {
      return this.presetLabel(this.ui.defaults?.agentPresetDefault ?? '');
    }
    if (key === 'model') {
      return this.modelLabelOf(this.ui.defaultModel?.provider ?? '', this.ui.defaultModel?.model ?? '');
    }
    if (key === 'permission') {
      return permissionLabel(this.ui.defaults?.permissionDefault ?? '');
    }
    return '';
  }

  /** Id of the workspace the session list is scoped to (for the header). */
  private currentWorkspaceTitle(): string {
    const workspace = activeWorkspace(this.ui);
    return workspace === undefined ? '' : workspace.title;
  }

  @Builder
  sectionHeader(title: string, key: string) {
    Row({ space: 8 }) {
      Text(title).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK)
      Text(this.sectionValue(key))
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.INK_WEAK)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
      SymbolGlyph(this.openSection === key ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(14)
        .fontColor([AppColors.INK_WEAK])
    }
    .width('100%')
    .height(AppSpacing.TOUCH)
    .onClick(() => {
      this.openSection = this.openSection === key ? '' : key;
    })
  }

  /** Header value for a current-session group, read lazily from this.ui. */
  private sessionValue(key: string): string {
    if (key === 'session-preset') {
      return this.presetLabel(this.sessionPresetId());
    }
    if (key === 'session-model') {
      return this.sessionModelLabel();
    }
    if (key === 'session-permission') {
      return this.sessionPermissionLabel();
    }
    return '';
  }

  @Builder
  sessionSectionHeader(title: string, key: string) {
    Row({ space: 8 }) {
      Text(title).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK)
      Text(this.sessionValue(key))
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.INK_WEAK)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
      SymbolGlyph(this.sessionSection === key ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(14)
        .fontColor([AppColors.INK_WEAK])
    }
    .width('100%')
    .height(AppSpacing.TOUCH)
    .onClick(() => {
      this.sessionSection = this.sessionSection === key ? '' : key;
    })
  }

  /**
   * Selectable rows. `selected` is deliberately NOT a @Builder parameter: a
   * by-value parameter is captured once and never refreshed after `publish()`,
   * so every row computes its own selected state from `this.ui` while it is
   * being laid out (that read is what registers the observed dependency).
   */
  @Builder
  presetOptionRow(preset: AgentPresetRow) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(preset.name).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).width('100%')
        Text(preset.description).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.presetOptionSelected(preset.id)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([AppColors.SUCCESS])
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 6, right: 6 })
    .backgroundColor(this.presetOptionSelected(preset.id) ? Glass.FILL_STRONG : '#00000000')
    .borderRadius(AppRadius.CARD_SMALL)
    .onClick(() => {
      this.run(async () => {
        await this.store.setDefault('agent-preset', preset.id);
      });
    })
  }

  @Builder
  defaultModelOptionRow(groupId: string, model: ModelRow) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(model.name).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).width('100%')
        Text(model.description).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.defaultModelSelected(groupId, model.id)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([AppColors.SUCCESS])
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 6, right: 6 })
    .backgroundColor(this.defaultModelSelected(groupId, model.id) ? Glass.FILL_STRONG : '#00000000')
    .borderRadius(AppRadius.CARD_SMALL)
    .onClick(() => {
      this.run(async () => {
        await this.store.saveDefaultModel(groupId, model.id, model.defaultEffort);
      });
    })
  }

  @Builder
  defaultPermissionOptionRow(option: PermissionOptionRow) {
    Row({ space: 8 }) {
      Text(permissionLabel(option.value)).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK)
        .layoutWeight(1)
      if (this.defaultPermissionSelected(option.value)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([AppColors.SUCCESS])
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 6, right: 6 })
    .backgroundColor(this.defaultPermissionSelected(option.value) ? Glass.FILL_STRONG : '#00000000')
    .borderRadius(AppRadius.CARD_SMALL)
    .onClick(() => {
      this.confirmPermission(option.value, true);
    })
  }

  @Builder
  sessionModelOptionRow(groupId: string, model: ModelRow) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(model.name).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).width('100%')
        Text(model.description).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.sessionModelSelected(groupId, model.id)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([AppColors.SUCCESS])
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 6, right: 6 })
    .backgroundColor(this.sessionModelSelected(groupId, model.id) ? Glass.FILL_STRONG : '#00000000')
    .borderRadius(AppRadius.CARD_SMALL)
    .onClick(() => {
      this.run(async () => {
        await this.store.selectModel(groupId, model.id, model.defaultEffort);
      });
    })
  }

  @Builder
  sessionPermissionOptionRow(option: PermissionOptionRow) {
    Row({ space: 8 }) {
      Text(permissionLabel(option.value)).fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK)
        .layoutWeight(1)
      if (this.sessionPermissionSelected(option.value)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([AppColors.SUCCESS])
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 6, right: 6 })
    .backgroundColor(this.sessionPermissionSelected(option.value) ? Glass.FILL_STRONG : '#00000000')
    .borderRadius(AppRadius.CARD_SMALL)
    .onClick(() => {
      this.confirmPermission(option.value, false);
    })
  }

  /**
   * Current session: the agent preset is fixed for a running session (the host
   * refuses to re-adopt it under another preset), so only the model and the
   * permission are switches — the same split as the DSH header vs composer.
   */
  @Builder
  sessionCard() {
    Column({ space: 4 }) {
      Text('当前会话').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
      Text(this.ui.activeSessionTitle.length > 0 ? this.ui.activeSessionTitle : '未选择会话')
        .fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).width('100%')
      Text(this.currentWorkspaceTitle().length > 0 ? `工作区：${this.currentWorkspaceTitle()}` : '未选择工作区')
        .fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')

      this.sessionSectionHeader('模式', 'session-preset')
      if (this.sessionSection === 'session-preset') {
        Text(this.sessionPresetId().length > 0
          ? `运行中的会话保持启动时的模式，新建会话用「部署默认值」里的 Agent 预设。`
          : '未同步到当前会话的模式。')
          .fontSize(10)
          .fontColor(AppColors.INK_WEAK)
          .width('100%')
          .padding({ left: 6, right: 6, bottom: 6 })
      }

      Divider().strokeWidth(1).color(Glass.BORDER_SOFT)

      this.sessionSectionHeader('模型', 'session-model')
      if (this.sessionSection === 'session-model') {
        if (this.ui.activeSessionId.length === 0) {
          Text('未选择会话').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
            .padding({ left: 6, bottom: 6 })
        }
        ForEach(this.ui.modelGroups, (group: ModelGroupRow) => {
          Text(group.name).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
            .padding({ top: 6, left: 6 })
          ForEach(group.models, (model: ModelRow) => {
            this.sessionModelOptionRow(group.id, model)
          }, (model: ModelRow) => `session-${group.id}-${model.id}`)
        }, (group: ModelGroupRow) => `session-group-${group.id}`)
      }

      Divider().strokeWidth(1).color(Glass.BORDER_SOFT)

      this.sessionSectionHeader('权限', 'session-permission')
      if (this.sessionSection === 'session-permission') {
        if (this.ui.activeSessionId.length === 0) {
          Text('未选择会话').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
            .padding({ left: 6, bottom: 6 })
        }
        ForEach(this.ui.permissionOptions, (option: PermissionOptionRow) => {
          this.sessionPermissionOptionRow(option)
        }, (option: PermissionOptionRow) => `session-permission-${option.value}`)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor(Glass.FILL)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
  }

  /** DSH gates the full-access preset behind an explicit risk confirmation. */
  private confirmPermission(value: string, asDefault: boolean): void {
    const apply = (): void => {
      this.run(async () => {
        if (asDefault) {
          await this.store.setDefault('permission', value);
        } else {
          await this.store.setPermission(value);
        }
      });
    };
    if (value !== 'danger-full-access') {
      apply();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '确认启用完全权限？',
      message: '启用完全权限后，智能体将减少确认步骤，并可直接执行更多操作，包括敏感操作、文件修改或外部命令。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '启用完全权限',
        fontColor: AppColors.DANGER,
        action: apply
      }
    });
  }

  @Builder
  defaultsCard() {
    Column({ space: 4 }) {
      Text('部署默认值').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
      this.sectionHeader('Agent 预设', 'preset')
      if (this.openSection === 'preset') {
        ForEach(this.ui.agentPresets, (preset: AgentPresetRow) => {
          this.presetOptionRow(preset)
        }, (preset: AgentPresetRow) => preset.id)
      }
      Divider().strokeWidth(1).color(Glass.BORDER_SOFT)
      this.sectionHeader('默认模型', 'model')
      if (this.openSection === 'model') {
        ForEach(this.ui.modelGroups, (group: ModelGroupRow) => {
          Text(group.name).fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
            .padding({ top: 6 })
          ForEach(group.models, (model: ModelRow) => {
            this.defaultModelOptionRow(group.id, model)
          }, (model: ModelRow) => `${group.id}-${model.id}`)
        }, (group: ModelGroupRow) => group.id)
      }
      Divider().strokeWidth(1).color(Glass.BORDER_SOFT)
      this.sectionHeader('默认权限', 'permission')
      if (this.openSection === 'permission') {
        ForEach(this.ui.permissionOptions, (option: PermissionOptionRow) => {
          this.defaultPermissionOptionRow(option)
        }, (option: PermissionOptionRow) => option.value)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor(Glass.FILL)
    .borderRadius(AppRadius.CARD)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
    .shadow(AppShadow.CARD)
  }

  @Builder
  themeChip(label: string, mode: string) {
    Text(label)
      .fontSize(AppFont.CAPTION)
      .fontColor(this.ui.themeMode === mode ? AppColors.PAPER : AppColors.DARK_INK)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(36)
      .backgroundColor(this.ui.themeMode === mode ? AppColors.BRAND : Glass.FILL_SUBTLE)
      .borderRadius(AppRadius.PILL)
      .onClick(() => {
        this.store.setThemeMode(mode).catch((failure: Error) => {
          this.error = failure.message;
          this.toast(failure.message);
        });
      })
  }

  @Builder
  action(label: string, primary: boolean, action: () => void) {
    Text(label)
      .fontSize(primary ? AppFont.SUBTITLE : AppFont.LABEL)
      .fontColor(primary ? AppColors.PAPER : AppColors.DARK_INK)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(primary ? 52 : 46)
      .backgroundColor(primary ? AppColors.BRAND : Glass.FILL)
      .borderRadius(AppRadius.CARD)
      .border({ width: Glass.BORDER_WIDTH, color: primary ? '#66BFD6FF' : Glass.BORDER_SOFT })
      .onClick(action)
  }

  build() {
    Stack() {
      HarnessBackground()
      Column({ space: AppSpacing.GAP }) {
        Row({ space: 10 }) {
          Stack() {
            SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(18).fontColor([AppColors.DARK_INK])
          }
          .width(38)
          .height(38)
          .borderRadius(AppRadius.CIRCLE)
          .backgroundColor(Glass.FILL)
          .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
          .onClick(() => {
            router.back();
          })
          Text('设置').fontSize(AppFont.HEADING).fontWeight(FontWeight.Bold).fontColor(AppColors.DARK_INK)
          Text('刷新').fontSize(AppFont.CAPTION).fontColor(AppColors.MIST)
            .layoutWeight(1).textAlign(TextAlign.End)
            .onClick(() => {
              this.run(async () => {
                await this.store.refreshSettings();
              });
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 4 })

        Scroll() {
          Column({ space: AppSpacing.GAP }) {
            Column({ space: 8 }) {
              Text('外观').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
              Row({ space: 8 }) {
                this.themeChip('跟随系统', 'system')
                this.themeChip('深色', 'dark')
                this.themeChip('浅色', 'light')
              }
              .width('100%')
              Text(this.ui.backgroundTaskActive ? '后台保活：运行中' : '后台保活：空闲')
                .fontSize(10)
                .fontColor(AppColors.INK_WEAK)
                .width('100%')
              // Reads `this.ui.showReasoning` here (not as a @Builder parameter):
              // the value is only refreshed when the builder reads it itself.
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text('显示 Agent 思考过程').fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).width('100%')
                  Text(this.ui.showReasoning
                    ? '开：思考内容可展开，仍会显示“深度求索中”'
                    : '关：不显示思考内容，只显示“深度求索中”')
                    .fontSize(10)
                    .fontColor(AppColors.INK_WEAK)
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.ui.showReasoning })
                  .selectedColor(AppColors.OK)
                  .onChange((isOn: boolean) => {
                    this.store.setShowReasoning(isOn).catch((failure: Error) => {
                      this.error = failure.message;
                      this.toast(failure.message);
                    });
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ top: 6 })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(14)
            .backgroundColor(Glass.FILL)
            .borderRadius(AppRadius.CARD)
            .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())

            this.sessionCard()
            this.defaultsCard()

            Column({ space: 8 }) {
              Text('连接').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
              Text(this.ui.endpoint.length > 0 ? this.ui.endpoint : '未配置')
                .fontSize(AppFont.LABEL).fontColor(AppColors.DARK_INK).width('100%')
              Text(`连接状态：${this.ui.connection} ${this.ui.connectionDetail}`)
                .fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
              Text(`能力：${this.ui.capabilities.join('、')}`)
                .fontSize(10).fontColor(AppColors.INK_WEAK).width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(14)
            .backgroundColor(Glass.FILL)
            .borderRadius(AppRadius.CARD)
            .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())

            if (this.error.length > 0) {
              Text(this.error).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
            }
            if (this.notice.length > 0) {
              Text(this.notice).fontSize(AppFont.CAPTION).fontColor(AppColors.OK).width('100%')
            }

            this.action('重新连接', true, () => {
              this.error = '';
              this.store.hasStoredCredential().then((saved: boolean) => {
                if (!saved) {
                  // Nothing to reconnect with (e.g. right after 解除配对): send the
                  // user to the scanner rather than showing an error with no way out.
                  router.pushUrl({ url: 'pages/PairingPage' });
                  return undefined;
                }
                return this.store.connectSaved().catch((failure: Error) => {
                  this.error = failure.message;
                });
              }).catch((failure: Error) => {
                this.error = failure.message;
              });
            })
            this.action('断开连接', false, () => {
              this.error = '';
              this.store.disconnect();
            })
            this.action(this.confirmUnpair ? '再次点击确认解除配对' : '解除配对', false, () => {
              if (!this.confirmUnpair) {
                this.confirmUnpair = true;
                return;
              }
              this.confirmUnpair = false;
              this.store.unpair().catch((failure: Error) => {
                this.error = failure.message;
              });
            })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: AppSpacing.PAGE,
        right: AppSpacing.PAGE,
        top: 12 + this.insetTop,
        bottom: 12 + this.insetBottom
      })
    }
    .width('100%')
    .height('100%')
  }
}
