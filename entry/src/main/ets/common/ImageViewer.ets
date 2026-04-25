@Component
export struct ImageViewer {
  @Prop urls: string[]
  @Prop initialIndex: number = 0
  onClose: () => void = () => {}

  @State currentIndex: number = 0
  @State zoomScale: number = 1

  aboutToAppear(): void {
    this.currentIndex = this.initialIndex
  }

  build() {
    Column() {
      Row() {
        Blank().layoutWeight(1)
        Text('✕').fontSize(24).fontColor(Color.White).padding({ right: 16, top: 16 })
          .onClick(() => { this.onClose() })
      }.width('100%')

      Swiper() {
        ForEach(this.urls, (url: string) => {
          Stack() {
            Image(url)
              .objectFit(ImageFit.Contain)
              .width('100%').height('100%')
              .scale({ x: this.zoomScale, y: this.zoomScale })
              .onError(() => {})
          }
          .width('100%').height('100%')
          .clip(true)
          .gesture(
            PinchGesture().onActionUpdate((event: GestureEvent) => {
              this.zoomScale = Math.max(1, Math.min(event.scale, 5))
            })
          )
        })
      }
      .index(this.initialIndex)
      .indicator(this.urls.length > 1)
      .loop(false)
      .onChange((index: number) => {
        this.currentIndex = index
        this.zoomScale = 1
      })
      .layoutWeight(1)
      .width('100%')

      if (this.urls.length > 1) {
        Text(`${this.currentIndex + 1} / ${this.urls.length}`)
          .fontSize(16).fontColor(Color.White).margin({ top: 12, bottom: 32 })
      } else {
        Blank().height(32)
      }
    }
    .width('100%').height('100%')
    .backgroundColor('#73000000')
  }
}
