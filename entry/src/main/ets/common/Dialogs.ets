/**
 * 确认对话框 + ActionSheet 组件
 */

// 确认对话框
@CustomDialog
export struct ConfirmDialog {
  controller: CustomDialogController
  @Prop title: string = ''
  @Prop message: string = ''
  @Prop confirmLabel: string = '确定'
  @Prop destructive: boolean = false
  onConfirm?: () => void
  onCancel?: () => void

  build() {
    Column() {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 8 })

      Text(this.message)
        .fontSize(14)
        .fontColor('#8E8E93')
        .margin({ bottom: 20 })

      Divider().color('#E5E5EA')

      Row() {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .fontColor('#007AFF')
          .onClick(() => {
            this.controller.close()
            if (this.onCancel) this.onCancel()
          })

        Divider().vertical(true).height(20).color('#E5E5EA')

        Button(this.confirmLabel)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .fontColor(this.destructive ? '#FF3B30' : '#007AFF')
          .fontWeight(FontWeight.Bold)
          .onClick(() => {
            this.controller.close()
            if (this.onConfirm) this.onConfirm()
          })
      }
      .height(44)
    }
    .width(300)
    .padding({ left: 20, right: 20 })
    .backgroundColor(Color.White)
    .borderRadius(14)
    .alignItems(HorizontalAlign.Center)
  }
}

// ActionSheet 选项接口
export interface ActionOption {
  label: string
  value: number
}

// ActionSheet
@CustomDialog
export struct ActionSheetDialog {
  controller: CustomDialogController
  @Prop title: string = ''
  options: ActionOption[] = []
  selected: number = 0
  onSelect?: (value: number) => void
  onCancel?: () => void

  build() {
    Column() {
      // 拖拽指示条
      Divider()
        .width(36)
        .height(4)
        .borderRadius(2)
        .color('#D1D1D6')
        .margin({ top: 8, bottom: 12 })

      Text(this.title)
        .fontSize(13)
        .fontColor('#8E8E93')
        .margin({ bottom: 8 })

      // 选项列表
      List() {
        ForEach(this.options, (opt: ActionOption) => {
          ListItem() {
            Row() {
              Text(opt.label)
                .fontSize(17)
                .layoutWeight(1)

              if (opt.value === this.selected) {
                Image($r('app.media.icon_checkmark'))
                  .width(17).height(17).fillColor('#007AFF')
              }
            }
            .width('100%')
            .height(50)
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              this.controller.close()
              if (this.onSelect) this.onSelect(opt.value)
            })
          }
        })
      }
      .width('100%')
      .divider({ strokeWidth: 0.5, color: '#E5E5EA' })

      // 取消按钮
      Divider().color('#E5E5EA').margin({ top: 8 })
      Button('取消')
        .width('100%')
        .height(50)
        .backgroundColor(Color.Transparent)
        .fontColor('#007AFF')
        .fontWeight(FontWeight.Bold)
        .onClick(() => {
          this.controller.close()
          if (this.onCancel) this.onCancel()
        })
    }
    .backgroundColor(Color.White)
    .borderRadius({ topLeft: 14, topRight: 14 })
    .padding({ bottom: 20 })
  }
}
