/**
 * Workspace files: browse the session cwd, download a file in chunks (SHA-256
 * verified) and preview text or images.
 */
import { router } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { GatewayStore } from '../store/GatewayStore';
import { FilePreviewRow, UI_KEY, UiSnapshot, emptyUiSnapshot } from '../store/UiState';
import { AppColors, AppFont, AppRadius, AppSpacing, Glass } from '../common/Constants';
import { FileEntryRow, PreviewKind, formatBytes } from '../protocol/Files';
import { messageContentView } from '../views/MessageContent';
import { HarnessBackground } from '../common/HarnessBackground';

@Entry
@Component
struct WorkspaceFilesPage {
  @StorageLink(UI_KEY) ui: UiSnapshot = emptyUiSnapshot();
  /** Status/navigation bar insets (vp) published by WindowChrome. */
  @StorageProp('gwInsetTop') insetTop: number = 0;
  @StorageProp('gwInsetBottom') insetBottom: number = 0;
  @State previewOpen: boolean = false;
  @State error: string = '';
  private store: GatewayStore = GatewayStore.current;

  async aboutToAppear(): Promise<void> {
    try {
      await this.store.browseWorkspaceFiles();
    } catch (failure) {
      this.error = (failure as Error).message;
    }
  }

  private async open(entry: FileEntryRow): Promise<void> {
    if (entry.isDirectory) {
      this.error = '';
      try {
        await this.store.browseWorkspaceFiles(entry.path);
      } catch (failure) {
        this.error = (failure as Error).message;
      }
      return;
    }
    this.error = '';
    await this.store.openWorkspaceFile(entry);
    const preview = this.store.filePreviewSnapshot();
    if (preview !== null) {
      this.previewOpen = true;
    }
  }

  private parentPath(): string {
    const current = this.ui.workspaceFilePath;
    const parts: string[] = [];
    for (const part of current.split('/')) {
      if (part.length > 0 && part !== '.') {
        parts.push(part);
      }
    }
    if (parts.length === 0) {
      return '.';
    }
    parts.pop();
    return parts.length === 0 ? '.' : parts.join('/');
  }

  @Builder
  previewSheet() {
    Column({ space: AppSpacing.GAP }) {
      Row({ space: 8 }) {
        Text(this.ui.filePreview?.name ?? '').fontSize(AppFont.SUBTITLE)
          .fontColor(AppColors.DARK_INK)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.ui.filePreview?.verified === true ? 'SHA-256 已校验' : '未校验')
          .fontSize(10)
          .fontColor(this.ui.filePreview?.verified === true ? AppColors.SUCCESS : AppColors.WARN)
      }
      .width('100%')

      Text(`${this.ui.filePreview?.path ?? ''} · ${formatBytes(this.ui.filePreview?.bytes ?? 0)}`)
        .fontSize(AppFont.CAPTION)
        .fontColor(AppColors.INK_WEAK)
        .width('100%')

      if (this.ui.filePreview?.kind === PreviewKind.IMAGE) {
        Image(`file://${this.ui.filePreview?.localPath ?? ''}`)
          .width('100%')
          .height(320)
          .objectFit(ImageFit.Contain)
          .backgroundColor(Glass.CODE_FILL)
          .borderRadius(AppRadius.CARD_SMALL)
      } else if (this.ui.filePreview?.kind === PreviewKind.MARKDOWN) {
        Scroll() {
          messageContentView(this.ui.filePreview?.text ?? '', false)
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        Scroll() {
          Text(this.ui.filePreview?.text ?? '（二进制文件，无法预览）')
            .fontSize(11)
            .fontColor(AppColors.DARK_INK)
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .padding(10)
        .backgroundColor(Glass.CODE_FILL)
        .borderRadius(AppRadius.CARD_SMALL)
      }

      if (this.ui.filePreview?.truncated === true) {
        Text('内容过大，仅显示前 200 KB').fontSize(10).fontColor(AppColors.WARN).width('100%')
      }

      Text('用其他应用打开')
        .fontSize(AppFont.LABEL)
        .fontColor(AppColors.DARK_INK)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(44)
        .backgroundColor(Glass.FILL)
        .borderRadius(AppRadius.CARD)
        .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
        .onClick(() => {
          const preview = this.ui.filePreview;
          if (preview === null) {
            return;
          }
          const want: Want = {
            action: 'ohos.want.action.viewData',
            uri: `file://${preview.localPath}`,
            type: preview.kind === PreviewKind.IMAGE ? 'image/*' : 'text/plain'
          };
          (getContext(this) as common.UIAbilityContext).startAbility(want).catch((failure: Error) => {
            this.error = `无法打开：${failure.message}`;
          });
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(AppSpacing.PAGE)
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
          Column({ space: 2 }) {
            Text('工作区文件').fontSize(AppFont.HEADING).fontWeight(FontWeight.Bold).fontColor(AppColors.DARK_INK)
            Text(this.ui.workspaceFilePath)
              .fontSize(AppFont.CAPTION)
              .fontColor(AppColors.INK_WEAK)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text(this.ui.workspaceFilePath === '.' ? '上一级' : '返回上级')
            .fontSize(AppFont.CAPTION)
            .fontColor(this.ui.workspaceFilePath === '.' ? AppColors.INK_WEAK : AppColors.MIST)
            .onClick(() => {
              if (this.ui.workspaceFilePath === '.') {
                return;
              }
              this.store.browseWorkspaceFiles(this.parentPath()).catch((failure: Error) => {
                this.error = failure.message;
              });
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.ui.download !== null) {
          Column({ space: 4 }) {
            Text(this.ui.download?.error.length === 0
              ? `${this.ui.download?.name ?? ''} ${formatBytes(this.ui.download?.received ?? 0)} / ${formatBytes(this.ui.download?.total ?? 0)}`
              : `下载失败：${this.ui.download?.error ?? ''}`)
              .fontSize(AppFont.CAPTION)
              .fontColor(this.ui.download?.error.length === 0 ? AppColors.INK_WEAK : AppColors.DANGER)
              .width('100%')
            Progress({
              value: this.ui.download?.received ?? 0,
              total: Math.max(this.ui.download?.total ?? 1, 1),
              type: ProgressType.Linear
            })
              .width('100%')
              .color(this.ui.download?.error.length === 0 ? AppColors.BRAND : AppColors.DANGER)
          }
          .width('100%')
        }

        if (this.error.length > 0) {
          Text(this.error).fontSize(AppFont.CAPTION).fontColor(AppColors.DANGER).width('100%')
        }

        if (this.ui.workspaceFiles.length === 0 && !this.ui.workspaceFilesLoading) {
          Text('该目录没有文件').fontSize(AppFont.CAPTION).fontColor(AppColors.INK_WEAK).width('100%')
        }

        List({ space: 0 }) {
          ForEach(this.ui.workspaceFiles, (entry: FileEntryRow) => {
            ListItem() {
              Row({ space: 10 }) {
                SymbolGlyph(entry.isDirectory ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text')).fontSize(16)
                Column({ space: 2 }) {
                  Text(entry.name)
                    .fontSize(AppFont.LABEL)
                    .fontColor(AppColors.DARK_INK)
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (!entry.isDirectory) {
                    Text(formatBytes(entry.bytes)).fontSize(10).fontColor(AppColors.INK_WEAK).width('100%')
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                if (!entry.isDirectory) {
                  Text('下载').fontSize(10).fontColor(AppColors.MIST)
                }
              }
              .width('100%')
              .height(AppSpacing.TOUCH)
              .onClick(() => {
                this.open(entry);
              })
            }
          }, (entry: FileEntryRow) => entry.path)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: Glass.BORDER_SOFT, startMargin: 12, endMargin: 0 })
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
    .bindSheet($$this.previewOpen, this.previewSheet(), {
      height: 620,
      backgroundColor: '#F20D2440',
      blurStyle: BlurStyle.NONE,
      showClose: true
    })
  }
}
