/**
 * Directory browser: pick an existing folder as a workspace or create a new one
 * (`directories` / `directory-create` / `workspace-create`).
 */
import { router } from '@kit.ArkUI';
import { GatewayStore } from '../store/GatewayStore';
import { UI_KEY, UiSnapshot, emptyUiSnapshot } from '../store/UiState';
import { AppColors, AppFont, AppRadius, AppSpacing, Glass } from '../common/Constants';
import { CrumbRow, FileEntryRow } from '../protocol/Files';
import { HarnessBackground } from '../common/HarnessBackground';

@Entry
@Component
struct WorkspaceBrowserPage {
  @StorageLink(UI_KEY) ui: UiSnapshot = emptyUiSnapshot();
  /** Status/navigation bar insets (vp) published by WindowChrome. */
  @StorageProp('gwInsetTop') insetTop: number = 0;
  @StorageProp('gwInsetBottom') insetBottom: number = 0;
  @State creating: boolean = false;
  @State newName: string = '';
  @State error: string = '';
  @State busy: boolean = false;
  private store: GatewayStore = GatewayStore.current;

  async aboutToAppear(): Promise<void> {
    try {
      await this.store.browseDirectories();
    } catch (failure) {
      this.error = (failure as Error).message;
    }
  }

  private directories(): FileEntryRow[] {
    const rows: FileEntryRow[] = [];
    for (const entry of this.ui.directoryEntries) {
      if (entry.isDirectory) {
        rows.push(entry);
      }
    }
    return rows;
  }

  private async run(action: () => Promise<void>): Promise<void> {
    this.busy = true;
    this.error = '';
    try {
      await action();
    } catch (failure) {
      this.error = (failure as Error).message;
    }
    this.busy = false;
  }

  @Builder
  glassCircle(glyph: Resource, action: () => void) {
    Stack() {
      SymbolGlyph(glyph).fontSize(18).fontColor([AppColors.DARK_INK])
    }
    .width(38)
    .height(38)
    .borderRadius(AppRadius.CIRCLE)
    .backgroundColor(Glass.FILL)
    .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, Glass.blurOptions())
    .onClick(action)
  }

  build() {
    Stack() {
      HarnessBackground()
      Column({ space: AppSpacing.GAP }) {
        Row({ space: 10 }) {
          this.glassCircle($r('sys.symbol.arrow_left'), () => {
            router.back();
          })
          Column({ space: 2 }) {
            Text('选择工作区目录').fontSize(AppFont.HEADING).fontWeight(FontWeight.Bold).fontColor(AppColors.DARK_INK)
            Text(this.ui.directoryPath.length > 0 ? this.ui.directoryPath : '读取中…')
              .fontSize(AppFont.CAPTION)
              .fontColor(AppColors.INK_WEAK)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.ui.directoryCrumbs, (crumb: CrumbRow) => {
              Text(crumb.name)
                .fontSize(AppFont.CAPTION)
                .fontColor(AppColors.MIST)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor(Glass.FILL_SUBTLE)
                .borderRadius(AppRadius.PILL)
                .onClick(() => {
                  this.run(async () => {
                    await this.store.browseDirectories(crumb.path);
                  });
                })
            }, (crumb: CrumbRow, index: number) => `${index}-${crumb.path}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .width('100%')

        Row({ space: 10 }) {
          Text('把当前目录设为工作区')
            .fontSize(AppFont.LABEL)
            .fontColor(AppColors.PAPER)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(46)
            .backgroundColor(AppColors.BRAND)
            .borderRadius(AppRadius.CARD)
            .onClick(() => {
              if (this.busy || this.ui.directoryPath.length === 0) {
                return;
              }
              this.run(async () => {
                await this.store.adoptWorkspace(this.ui.directoryPath);
                router.back();
              });
            })
          Text('新建文件夹')
            .fontSize(AppFont.LABEL)
            .fontColor(AppColors.DARK_INK)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(46)
            .backgroundColor(Glass.FILL)
            .borderRadius(AppRadius.CARD)
            .border({ width: Glass.BORDER_WIDTH, color: Glass.BORDER_SOFT })
            .onClick(() => {
              this.creating = !this.creating;
              this.newName = '';
            })
        }
        .width('100%')

        if (this.creating) {
          Row({ space: 10 }) {
            TextInput({ placeholder: '新文件夹名称', text: this.newName })
              .layoutWeight(1)
              .height(44)
              .fontSize(AppFont.LABEL)
              .fontColor(AppColors.DARK_INK)
              .placeholderColor(AppColors.INK_WEAK)
              .backgroundColor(Glass.FILL_SUBTLE)
              .borderRadius(AppRadius.INPUT)
              .onChange((value: string) => {
                this.newName = value;
              })
            Text('创建')
              .fontSize(AppFont.LABEL)
              .fontColor(AppColors.PAPER)
              .textAlign(TextAlign.Center)
              .width(80)
              .height(44)
              .backgroundColor(AppColors.BRAND)
              .borderRadius(AppRadius.INPUT)
              .onClick(() => {
                const name = this.newName.replace(/^\s+|\s+$/g, '');
                if (name.length === 0 || this.busy) {
                  return;
                }
                const parent = this.ui.directoryPath;
                this.run(async () => {
                  const target = await this.store.createWorkspaceFolder(parent, name);
                  this.creating = false;
                  await this.store.browseDirectories(parent);
                  this.error = `已创建工作区：${target}`;
                });
              })
          }
          .width('100%')
        }

        if (this.error.length > 0) {
          Text(this.error).fontSize(AppFont.CAPTION).fontColor(AppColors.WARN).width('100%')
        }

        List({ space: 0 }) {
          ForEach(this.directories(), (entry: FileEntryRow) => {
            ListItem() {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.folder')).fontSize(16)
                Text(entry.name)
                  .fontSize(AppFont.BODY)
                  .fontColor(AppColors.DARK_INK)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppColors.INK_WEAK])
              }
              .width('100%')
              .height(AppSpacing.TOUCH)
              .onClick(() => {
                this.run(async () => {
                  await this.store.browseDirectories(entry.path);
                });
              })
            }
          }, (entry: FileEntryRow) => entry.path)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: Glass.BORDER_SOFT, startMargin: 12, endMargin: 0 })
        .scrollBar(BarState.Off)

        Text(this.ui.directoryLoading ? '读取中…' : `${this.directories().length} 个子目录`)
          .fontSize(AppFont.CAPTION)
          .fontColor(AppColors.INK_WEAK)
          .width('100%')
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
