import media from '@ohos.multimedia.media'
import { AppColors } from './Constants'

function fmtTime(totalSeconds: number): string {
  const m: number = Math.floor(totalSeconds / 60)
  const s: number = Math.floor(totalSeconds % 60)
  let result: string = ''
  if (m < 10) result += '0'
  result += m + ':'
  if (s < 10) result += '0'
  result += s
  return result
}

@Component
export struct AudioPlayer {
  @Prop @Watch('onSrcChanged') src: string = ''
  @State private isPlaying: boolean = false
  @State private isLoading: boolean = true
  @State private hasError: boolean = false
  @State private currentTime: number = 0
  @State private duration: number = 0

  private player: media.AVPlayer | null = null
  private isCompleted: boolean = false
  private seeking: boolean = false

  aboutToAppear(): void {
    if (this.src.length > 0) {
      this.initPlayer()
    }
  }

  aboutToDisappear(): void {
    this.releasePlayer()
  }

  private onSrcChanged(): void {
    this.releasePlayer()
    this.isPlaying = false
    this.isLoading = true
    this.hasError = false
    this.currentTime = 0
    this.duration = 0
    this.isCompleted = false
    if (this.src.length > 0) {
      this.initPlayer()
    } else {
      this.isLoading = false
    }
  }

  private releasePlayer(): void {
    const p: media.AVPlayer | null = this.player
    if (p) {
      try {
        p.release()
      } catch (e) {}
      this.player = null
    }
  }

  private async initPlayer(): Promise<void> {
    try {
      this.isLoading = true
      this.currentTime = 0
      this.duration = 0
      const p: media.AVPlayer = await media.createAVPlayer()
      this.player = p
      this.setupCallbacks(p)
      p.url = this.src
    } catch (e) {
      this.hasError = true
      this.isLoading = false
    }
  }

  private setupCallbacks(p: media.AVPlayer): void {
    p.on('stateChange', (state: string): void => {
      switch (state) {
        case 'initialized':
          p.prepare()
          break
        case 'prepared':
          this.isLoading = false
          break
        case 'playing':
          this.isPlaying = true
          break
        case 'paused':
          this.isPlaying = false
          break
        case 'completed':
          this.isPlaying = false
          this.isCompleted = true
          break
      }
    })

    p.on('durationUpdate', (dur: number): void => {
      this.duration = Math.floor(dur / 1000)
    })

    p.on('timeUpdate', (time: number): void => {
      if (!this.seeking) {
        this.currentTime = Math.floor(time / 1000)
      }
    })

    p.on('error', (): void => {
      this.hasError = true
      this.isLoading = false
    })
  }

  private togglePlay(): void {
    const p: media.AVPlayer | null = this.player
    if (!p || this.isLoading || this.hasError) {
      return
    }
    if (this.isPlaying) {
      p.pause()
    } else if (this.isCompleted) {
      this.isCompleted = false
      p.seek(0)
      p.play()
    } else {
      p.play()
    }
  }

  private onSeek(value: number): void {
    const p: media.AVPlayer | null = this.player
    if (!p || this.isLoading || this.hasError) {
      return
    }
    this.seeking = true
    this.currentTime = value
    p.seek(value * 1000)
    this.seeking = false
  }

  build() {
    Row() {
      Image($r('app.media.icon_music'))
        .width(18).height(18)
        .fillColor(this.isPlaying ? AppColors.primary : AppColors.textTertiary)
        .onClick(() => { this.togglePlay() })

      if (this.isLoading) {
        LoadingProgress().width(14).height(14).color(AppColors.textTertiary)
          .margin({ left: 8 })
      } else if (this.hasError) {
        Text('加载失败').fontSize(12).fontColor(AppColors.textTertiary)
          .margin({ left: 8 })
      } else {
        Slider({
          value: this.currentTime,
          min: 0,
          max: this.duration > 0 ? this.duration : 1,
          step: 1,
          style: SliderStyle.OutSet
        })
          .blockColor(AppColors.primary)
          .trackColor(AppColors.separator)
          .selectedColor(AppColors.primary)
          .width(0).layoutWeight(1)
          .onChange((value: number) => { this.onSeek(value) })
      }

      if (!this.isLoading && !this.hasError) {
        Text(fmtTime(this.currentTime) + ' / ' + fmtTime(this.duration))
          .fontSize(11).fontColor(AppColors.textTertiary)
      }
    }
    .padding({ left: 6, right: 8, top: 4, bottom: 4 })
    .backgroundColor(AppColors.bgSecondary)
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .width('100%').height(36)
  }
}
