import { floatingLayerStore, FloatingLayerStoreClass, FloatingPage } from '../store/FloatingLayerStore'
import { AppColors } from '../common/Constants'
import { ImageViewer } from '../common/ImageViewer'
import { ProfileCardPopup } from '../common/ProfileCardPopup'
import { ReplyDialog } from '../common/ReplyDialog'

@Component
export struct FloatingLayerComponent {
  @State private floating: FloatingLayerStoreClass = floatingLayerStore
  @Prop currentBreakpoint: string = 'sm'

  build() {
    Stack() {
      if (this.floating.top === FloatingPage.IMAGE_VIEWER) {
        ImageViewer({
          urls: this.floating.imageViewerUrls,
          initialIndex: this.floating.imageViewerIndex,
          onClose: () => { this.floating.remove(FloatingPage.IMAGE_VIEWER) }
        })
      }
      if (this.floating.top === FloatingPage.PROFILE_CARD) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#33000000')
            .onClick(() => { this.floating.remove(FloatingPage.PROFILE_CARD) })
          ProfileCardPopup({
            targetUid: this.floating.profileCardUid,
            currentBreakpoint: this.currentBreakpoint,
            onClose: () => { this.floating.remove(FloatingPage.PROFILE_CARD) }
          })
          .position({
            x: this.floating.profileCardX,
            y: this.floating.profileCardY
          })
        }
        .width('100%').height('100%')
      }
      if (this.floating.top === FloatingPage.REPLY_DIALOG) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#33000000')

          Column().width('100%').height('100%')
            .onClick(() => { this.floating.notifyReplyCloseRequested() })

          Column() {
            ReplyDialog({
              dialogTitle: this.floating.replyDialogTitle,
              onSend: this.floating.replyOnSend,
              onClose: () => {
                this.floating.registerReplyCloseHandler(null)
                this.floating.remove(FloatingPage.REPLY_DIALOG)
              }
            })
          }
          .align(Alignment.Center)
        }
        .width('100%').height('100%')
      }

      if (this.floating.top === FloatingPage.CONFIRM_DIALOG) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#66000000')
            .onClick(() => { this.floating.hideConfirm() })
          Column() {
            Text(this.floating.confirmTitle)
              .fontSize(17).fontWeight(FontWeight.Bold)
              .margin({ top: 20, bottom: 8 })
            Text(this.floating.confirmMessage)
              .fontSize(14).fontColor('#8E8E93')
              .margin({ bottom: 20 })
            Divider().color('#E5E5EA')
            Row() {
              Button('取消')
                .layoutWeight(1).backgroundColor(Color.Transparent).fontColor('#007AFF')
                .onClick(() => { this.floating.hideConfirm() })
              Divider().vertical(true).height(20).color('#E5E5EA')
              Button(this.floating.confirmLabel)
                .layoutWeight(1).backgroundColor(Color.Transparent)
                .fontColor(this.floating.confirmDestructive ? '#FF3B30' : '#007AFF')
                .fontWeight(FontWeight.Bold)
                .onClick(() => {
                  const handler = this.floating.confirmOnConfirm
                  this.floating.hideConfirm()
                  if (handler) {
                    handler()
                  }
                })
            }.height(44)
          }
          .width(300).padding({ left: 20, right: 20 })
          .backgroundColor(Color.White).borderRadius(14)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%').height('100%')
      }

      if (this.floating.top === FloatingPage.PAGE_PICKER) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#33000000')
            .onClick(() => { this.floating.remove(FloatingPage.PAGE_PICKER) })
          Column() {
            Text('选择页面').fontSize(14).fontColor(AppColors.textPrimary).fontWeight(FontWeight.Bold)
              .padding({ top: 12, bottom: 8 }).width('100%').textAlign(TextAlign.Center)
            Divider().color(AppColors.separator)
            Scroll() {
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
                ForEach(this.buildPageArray(), (p: number) => {
                  Text(String(p)).fontSize(15)
                    .fontColor(p === this.floating.pagePickerCurrentPage ? AppColors.primary : AppColors.textPrimary)
                    .fontWeight(p === this.floating.pagePickerCurrentPage ? FontWeight.Bold : FontWeight.Regular)
                    .width(40).height(40).textAlign(TextAlign.Center).borderRadius(8)
                    .backgroundColor(p === this.floating.pagePickerCurrentPage ? AppColors.primaryLight : Color.Transparent)
                    .onClick(() => {
                      const onSelect = this.floating.pagePickerOnSelect
                      this.floating.remove(FloatingPage.PAGE_PICKER)
                      if (onSelect) {
                        onSelect(p)
                      }
                    })
                }, (p: number) => String(p))
              }.width('100%')
            }.width('100%').height(120).align(Alignment.TopStart)
          }
          .width(220).height(180).backgroundColor(Color.White).borderRadius(12)
            .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
            .position({ x: this.floating.pagePickerX, y: this.floating.pagePickerY })
        }
        .width('100%').height('100%').alignContent(Alignment.BottomEnd)
      }

      if (this.floating.replyConfirmActive) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#33000000')
            .onClick(() => {
              this.floating.hideReplyConfirm()
            })
          Column() {
            Text('放弃编辑？').fontSize(17).fontWeight(FontWeight.Bold).fontColor(AppColors.textPrimary)
              .margin({ top: 20 })
            Text('已保存为草稿，下次编辑可恢复').fontSize(14).fontColor(AppColors.textSecondary)
              .margin({ top: 8 })
            Row() {
              Text('继续编辑').fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppColors.primary)
                .layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 14, bottom: 14 })
                .onClick(() => {
                  this.floating.hideReplyConfirm()
                })
              Divider().vertical(true).height(24).color(AppColors.separator).alignSelf(ItemAlign.Center)
              Text('放弃').fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppColors.destructive)
                .layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 14, bottom: 14 })
                .onClick(() => {
                  this.floating.confirmAbandon()
                })
            }.width('100%').margin({ top: 16 })
            .border({ width: { top: 0.5 }, color: AppColors.separator })
          }
          .width(270)
          .backgroundColor(AppColors.bg)
          .borderRadius(14)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%').height('100%')
      }
    }
    .width('100%').height('100%')
    .hitTestBehavior(
      (this.floating.top === FloatingPage.IMAGE_VIEWER ||
       this.floating.top === FloatingPage.PROFILE_CARD ||
       this.floating.top === FloatingPage.REPLY_DIALOG ||
       this.floating.top === FloatingPage.CONFIRM_DIALOG ||
       this.floating.top === FloatingPage.PAGE_PICKER)
        ? HitTestMode.Default : HitTestMode.None
    )
  }

  private buildPageArray(): number[] {
    const arr: number[] = []
    for (let i: number = 1; i <= this.floating.pagePickerTotalPages; i++) {
      arr.push(i)
    }
    return arr
  }
}
