/**
 * AI 配置管理面板。
 *
 * 管理自定义 AI 提供方配置：创建、编辑、删除、测试连接。
 * 采用内联可展开卡片模式，新建/编辑在同一页面内完成，
 * 无需切换模式。仅新建时显示平台预设芯片辅助填写。
 */

import { appStore } from '../../store/AppStore'
import { AppColors } from '../../common/constants/Constants'
import { PanelNavBar } from '../../common/components/PanelNavBar'
import { ConfirmDialog, ActionSheetDialog, ActionOption } from '../../common/dialogs/Dialogs'
import { AiProviderProfile, AiTestResult } from '../../model/AiConfig'
import { PROVIDER_PRESETS } from '../../service/ai/AiModelPresets'
import { testConnection, listModels } from '../../service/ai/OpenAiCompatibleClient'
import type { AiProviderPreset } from '../../service/ai/AiModelPresets'
import { AiSetupGuide } from './AiSetupGuide'
import { PreferencesStore } from '../../common/infra/PreferencesStore'

/** 引导已显示的存储键 */
const KEY_AI_GUIDE_SHOWN: string = 'ai_guide_shown'

/** 新建方案的哨兵 ID */
const NEW_ID: string = '__new__'

@Component
export struct AiSettingsPanel {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @State profiles: AiProviderProfile[] = []
  @State expandedProfileId: string = ''
  @State editNameInput: string = ''
  @State editEndpointInput: string = ''
  @State editApiKeyInput: string = ''
  @State editModelInput: string = ''
  @State testResultMessage: string = ''
  @State testing: boolean = false
  @State fetchingModels: boolean = false
  @State fetchedModels: string[] = []
  @State guideShown: boolean = false

  private prefStore: PreferencesStore = new PreferencesStore()

  /** 是否正在新建方案 */
  private isNew(): boolean {
    return this.expandedProfileId === NEW_ID
  }

  // ============== Dialog Controllers ==============

  deleteConfirmController?: CustomDialogController
  providerPickerController?: CustomDialogController
  guideController?: CustomDialogController
  discardConfirmController?: CustomDialogController

  aboutToAppear(): void {
    this.syncProfiles()
    this.loadGuideState()
  }

  aboutToDisappear(): void {
    this.deleteConfirmController = undefined
    this.providerPickerController = undefined
    this.guideController = undefined
    this.discardConfirmController = undefined
  }

  // ============== Data Sync ==============

  private syncProfiles(): void {
    this.profiles = appStore.settings.aiProfiles
  }

  private async loadGuideState(): Promise<void> {
    try {
      await this.prefStore.init(this.getUIContext().getHostContext() as Context, 'nga_ai_guide')
      const shown: string | null = await this.prefStore.getString(KEY_AI_GUIDE_SHOWN)
      this.guideShown = shown === '1'
    } catch (e) {
      this.guideShown = false
    }
  }

  private async markGuideShown(): Promise<void> {
    this.guideShown = true
    try {
      await this.prefStore.putString(KEY_AI_GUIDE_SHOWN, '1')
      this.prefStore.scheduleFlush()
    } catch (e) {
      // 静默失败
    }
  }

  showGuide(): void {
    const ctrl: CustomDialogController = new CustomDialogController({
      builder: AiSetupGuide(),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    })
    this.guideController = ctrl
    ctrl.open()
    this.markGuideShown()
  }

  // ============== Card Expand / Collapse ==============

  /**
   * 展开指定卡片。
   *
   * 若当前有未保存的编辑，先弹出放弃确认。
   *
   * @param profileId - 已有配置的 ID，或 NEW_ID 表示新建
   */
  private expandCard(profileId: string): void {
    if (this.expandedProfileId === profileId) {
      return
    }
    if (this.hasUnsavedEdit()) {
      this.showDiscardConfirm((): void => {
        this.doExpandCard(profileId)
      })
      return
    }
    this.doExpandCard(profileId)
  }

  private doExpandCard(profileId: string): void {
    this.expandedProfileId = profileId
    this.testResultMessage = ''
    this.fetchedModels = []

    if (profileId === NEW_ID) {
      this.editNameInput = ''
      this.editEndpointInput = ''
      this.editApiKeyInput = ''
      this.editModelInput = ''
    } else {
      const profile: AiProviderProfile | null = this.findProfile(profileId)
      if (profile) {
        this.editNameInput = profile.name
        this.editEndpointInput = profile.endpoint
        this.editApiKeyInput = ''
        this.editModelInput = profile.modelName
      }
    }
  }

  /** 折叠当前展开的卡片，若有未保存修改则先确认 */
  private collapseCard(): void {
    if (this.hasUnsavedEdit()) {
      this.showDiscardConfirm((): void => {
        this.doCollapse()
      })
      return
    }
    this.doCollapse()
  }

  private doCollapse(): void {
    this.expandedProfileId = ''
    this.clearEditBuffers()
  }

  private showDiscardConfirm(onConfirm: () => void): void {
    this.discardConfirmController = new CustomDialogController({
      builder: ConfirmDialog({
        title: '放弃修改',
        message: '当前编辑的内容尚未保存，确定要放弃吗？',
        confirmLabel: '放弃',
        destructive: false,
        onConfirm: onConfirm,
        onCancel: (): void => {}
      }),
      autoCancel: true,
      customStyle: true
    })
    this.discardConfirmController.open()
  }

  /**
   * 判断当前展开的卡片是否有未保存的修改。
   *
   * @returns 是否有未保存修改
   */
  private hasUnsavedEdit(): boolean {
    if (this.expandedProfileId.length === 0) {
      return false
    }
    if (this.expandedProfileId === NEW_ID) {
      return this.editNameInput.length > 0 ||
        this.editEndpointInput.length > 0 ||
        this.editApiKeyInput.length > 0 ||
        this.editModelInput.length > 0
    }
    const profile: AiProviderProfile | null = this.findProfile(this.expandedProfileId)
    if (!profile) {
      return false
    }
    return this.editNameInput !== profile.name ||
      this.editEndpointInput !== profile.endpoint ||
      this.editApiKeyInput.length > 0 ||
      this.editModelInput !== profile.modelName
  }

  private clearEditBuffers(): void {
    this.editNameInput = ''
    this.editEndpointInput = ''
    this.editApiKeyInput = ''
    this.editModelInput = ''
    this.testResultMessage = ''
    this.fetchedModels = []
  }

  // ============== Profile CRUD ==============

  private findProfile(id: string): AiProviderProfile | null {
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id === id) {
        return this.profiles[i]
      }
    }
    return null
  }

  private isActiveProfile(id: string): boolean {
    const idx: number = appStore.settings.activeAiConfigIndex
    if (idx < 0 || idx >= this.profiles.length) {
      return false
    }
    return this.profiles[idx].id === id
  }

  saveProfile(): void {
    if (!this.editNameInput || this.editNameInput.trim().length === 0) {
      appStore.showToast('请输入方案名称')
      return
    }
    if (!this.editEndpointInput || this.editEndpointInput.trim().length === 0) {
      appStore.showToast('请输入服务地址')
      return
    }
    if (!this.editModelInput || this.editModelInput.trim().length === 0) {
      appStore.showToast('请输入模型名称')
      return
    }

    const profile: AiProviderProfile = new AiProviderProfile()
    profile.name = this.editNameInput.trim()
    profile.endpoint = this.editEndpointInput.trim()
    profile.modelName = this.editModelInput.trim()

    if (this.expandedProfileId === NEW_ID) {
      profile.apiKey = this.editApiKeyInput
      appStore.addAiProfile(profile)
      appStore.showToast('已添加并切换到 ' + profile.name)
      appStore.setActiveAiConfig(appStore.settings.aiProfiles.length - 1)
    } else {
      profile.id = this.expandedProfileId
      if (this.editApiKeyInput.length > 0) {
        profile.apiKey = this.editApiKeyInput
      } else {
        const old: AiProviderProfile | null = this.findProfile(this.expandedProfileId)
        profile.apiKey = old ? old.apiKey : ''
      }
      appStore.updateAiProfile(profile)
      appStore.showToast('配置已更新')
    }

    this.syncProfiles()
    this.doCollapse()
  }

  deleteProfile(id: string): void {
    const profile: AiProviderProfile | null = this.findProfile(id)
    const name: string = profile ? profile.name : '此配置'

    this.deleteConfirmController = new CustomDialogController({
      builder: ConfirmDialog({
        title: '删除 AI 配置',
        message: this.isActiveProfile(id)
          ? '你将删除当前正在使用的配置「' + name + '」。\n删除后系统会自动切换为系统默认 AI，AI 功能仍可正常使用。'
          : '确定要删除配置「' + name + '」吗？\n删除后该配置将从列表中移除。',
        confirmLabel: '删除',
        destructive: true,
        icon: $r('app.media.icon_delete'),
        onConfirm: (): void => {
          appStore.deleteAiProfile(id)
          this.syncProfiles()
          if (this.expandedProfileId === id) {
            this.doCollapse()
          }
        },
        onCancel: (): void => {}
      }),
      autoCancel: true,
      customStyle: true
    })
    this.deleteConfirmController.open()
  }

  // ============== Provider Preset Picker ==============

  showProviderPresetPicker(): void {
    const options: ActionOption[] = []
    for (let i = 0; i < PROVIDER_PRESETS.length; i++) {
      const opt: ActionOption = {
        label: PROVIDER_PRESETS[i].name + ' - ' + PROVIDER_PRESETS[i].description,
        value: i
      }
      options.push(opt)
    }

    this.providerPickerController = new CustomDialogController({
      builder: ActionSheetDialog({
        title: '选择 AI 平台',
        options: options,
        selected: -1,
        onSelect: (v: number): void => {
          const preset: AiProviderPreset = PROVIDER_PRESETS[v]
          this.editNameInput = preset.name
          this.editEndpointInput = preset.endpoint
          this.editApiKeyInput = ''
          this.editModelInput = ''
          this.testResultMessage = ''
          this.fetchedModels = []
          this.expandedProfileId = NEW_ID
        }
      }),
      autoCancel: true,
      customStyle: true
    })
    this.providerPickerController.open()
  }

  /** 新建时切换预设平台 */
  private applyPreset(preset: AiProviderPreset): void {
    this.editNameInput = preset.name
    this.editEndpointInput = preset.endpoint
    this.editModelInput = ''
    this.testResultMessage = ''
    this.fetchedModels = []
  }

  // ============== Model List ==============

  async fetchModels(): Promise<void> {
    if (this.fetchingModels) {
      return
    }
    if (!this.editEndpointInput || this.editEndpointInput.trim().length === 0) {
      appStore.showToast('请先填写服务地址')
      return
    }

    this.fetchingModels = true
    this.fetchedModels = []

    const tempProfile: AiProviderProfile = new AiProviderProfile()
    tempProfile.endpoint = this.editEndpointInput.trim()
    if (this.editApiKeyInput.length > 0) {
      tempProfile.apiKey = this.editApiKeyInput
    }

    try {
      const models: string[] = await listModels(tempProfile)
      this.fetchedModels = models
      if (models.length === 0) {
        appStore.showToast('未获取到模型列表，请手动输入')
      }
    } catch (e) {
      const err: Error = e as Error
      appStore.showToast('获取模型列表失败：' + (err.message || '未知错误'))
    } finally {
      this.fetchingModels = false
    }
  }

  selectModel(modelName: string): void {
    this.editModelInput = modelName
  }

  // ============== Connection Test ==============

  async doTestConnection(): Promise<void> {
    if (this.testing) {
      return
    }
    if (!this.editEndpointInput || !this.editModelInput) {
      appStore.showToast('请先填写服务地址和模型名称')
      return
    }

    // 若用户未重新输入 Key，从已保存的 profile 中回退
    let apiKey: string = this.editApiKeyInput
    if (apiKey.length === 0 && !this.isNew() && this.expandedProfileId.length > 0) {
      const saved: AiProviderProfile | null = this.findProfile(this.expandedProfileId)
      apiKey = saved ? saved.apiKey : ''
    }

    if (apiKey.length === 0) {
      appStore.showToast('请先填写 API 密钥')
      return
    }

    this.testing = true
    this.testResultMessage = ''

    const tempProfile: AiProviderProfile = new AiProviderProfile()
    tempProfile.endpoint = this.editEndpointInput.trim()
    tempProfile.apiKey = apiKey
    tempProfile.modelName = this.editModelInput.trim()

    try {
      const result: AiTestResult = await testConnection(tempProfile)
      if (result.success) {
        this.testResultMessage = '连接成功 · 耗时 ' + result.durationMs + 'ms\n' + result.message
      } else {
        this.testResultMessage = '连接失败 · ' + result.errorMessage
      }
    } catch (e) {
      const err: Error = e as Error
      this.testResultMessage = '连接失败 · ' + (err.message || '未知错误')
    } finally {
      this.testing = false
    }
  }

  // ============== Build ==============

  build() {
    Stack() {
      Column() {
        PanelNavBar({ title: 'AI 配置' })
          .width('100%')

        Scroll() {
          Column() {
            // 系统默认行
            this.SystemDefaultRow()

            // 配置卡片列表
            if (this.profiles.length === 0 && !this.isNew()) {
              this.EmptyHint()
            } else {
              ForEach(this.profiles, (profile: AiProviderProfile) => {
                this.ProfileCard(profile)
              }, (profile: AiProviderProfile): string => profile.id)
            }

            // 新建卡片
            if (this.isNew()) {
              this.NewProfileCard()
            }

            // 添加按钮
            this.AddButton()

            // 帮助入口
            this.HelpEntry()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 32, top: 8 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.bg)
    }
    .width('100%')
    .height('100%')
  }

  // ============== @Builder Sub-Components ==============

  @Builder
  SystemDefaultRow() {
    Row() {
      Radio({ value: 'system', group: 'aiProvider' })
        .checked(appStore.settings.activeAiConfigIndex < 0)
        .onChange((checked: boolean) => {
          if (checked) {
            appStore.setActiveAiConfig(-1)
            this.syncProfiles()
          }
        })
        .width(20)
        .height(20)

      Column() {
        Text('系统默认 AI')
          .fontSize(16)
          .fontColor(AppColors.textPrimary)
          .fontWeight(FontWeight.Medium)

        Text('鸿蒙原生 AI 能力')
          .fontSize(12)
          .fontColor(AppColors.textTertiary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('92%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(AppColors.bgTertiary)
    .borderRadius(12)
    .margin({ top: 12 })
  }

  @Builder
  ProfileCard(profile: AiProviderProfile) {
    Column() {
      // 头部
      this.ProfileCardHeader(profile)

      // 展开体
      if (this.expandedProfileId === profile.id) {
        Divider().color(AppColors.separator).width('100%').margin({ bottom: 4 })
        this.ProfileCardBody()
      }
    }
    .width('92%')
    .backgroundColor(AppColors.bgTertiary)
    .borderRadius(12)
    .margin({ top: 8 })
  }

  @Builder
  ProfileCardHeader(profile: AiProviderProfile) {
    Row() {
      // Radio 区域 — 点击只切换激活，不展开卡片
      Row() {
        Radio({ value: profile.id, group: 'aiProvider' })
          .checked(this.isActiveProfile(profile.id))
          .onChange((checked: boolean) => {
            if (checked) {
              const idx: number = -1
              // 在 profiles 数组中查找索引
              for (let i = 0; i < this.profiles.length; i++) {
                if (this.profiles[i].id === profile.id) {
                  appStore.setActiveAiConfig(i)
                  this.syncProfiles()
                  break
                }
              }
            }
          })
          .width(20)
          .height(20)
      }
      .width(36)
      .height(48)
      .justifyContent(FlexAlign.Center)

      // 信息区域 — 点击展开/折叠
      Column() {
        Text(profile.name)
          .fontSize(15)
          .fontColor(AppColors.textPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(profile.endpoint)
          .fontSize(11)
          .fontColor(AppColors.textTertiary)
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        if (this.expandedProfileId === profile.id) {
          this.collapseCard()
        } else {
          this.expandCard(profile.id)
        }
      })

      // 删除按钮
      Text('删除')
        .fontSize(12)
        .fontColor('#E45D4C')
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .onClick(() => {
          this.deleteProfile(profile.id)
        })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 12, bottom: 12 })
  }

  @Builder
  ProfileCardBody() {
    Column() {
      // 方案名称
      Column() {
        Text('方案名称')
          .fontSize(13)
          .fontColor(AppColors.textSecondary)
          .width('100%')
          .margin({ bottom: 4 })

        TextInput({ placeholder: '为这个方案起个名字', text: this.editNameInput })
          .onChange((v: string) => {
            this.editNameInput = v
          })
          .width('100%')
          .height(40)
          .backgroundColor(AppColors.bgSecondary)
          .borderRadius(8)
          .fontSize(14)
          .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .margin({ bottom: 10 })

      // 服务地址
      Column() {
        Text('服务地址')
          .fontSize(13)
          .fontColor(AppColors.textSecondary)
          .width('100%')
          .margin({ bottom: 4 })

        TextInput({ placeholder: 'https://api.deepseek.com/v1', text: this.editEndpointInput })
          .onChange((v: string) => {
            this.editEndpointInput = v
          })
          .width('100%')
          .height(40)
          .backgroundColor(AppColors.bgSecondary)
          .borderRadius(8)
          .fontSize(14)
          .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .margin({ bottom: 10 })

      // API 密钥 + 测试按钮
      Row() {
        Column() {
          Text('API 密钥')
            .fontSize(13)
            .fontColor(AppColors.textSecondary)
            .width('100%')
            .margin({ bottom: 4 })

          TextInput({ placeholder: 'sk-...', text: this.editApiKeyInput })
            .type(InputType.Password)
            .onChange((v: string) => {
              this.editApiKeyInput = v
            })
            .width('100%')
            .height(40)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(8)
            .fontSize(14)
            .padding({ left: 12, right: 12 })
        }
        .layoutWeight(1)

        Text(this.testing ? '测试中...' : '测试连接')
          .fontSize(12)
          .fontColor(this.testing ? AppColors.textTertiary : AppColors.primary)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .margin({ left: 8, top: 18 })
          .border({
            width: 1,
            color: this.testing ? AppColors.textTertiary : AppColors.primary,
            style: BorderStyle.Solid
          })
          .borderRadius(6)
          .onClick(() => {
            this.doTestConnection()
          })
      }
      .width('100%')
      .margin({ bottom: 4 })

      // 测试结果
      if (this.testResultMessage.length > 0) {
        Text(this.testResultMessage)
          .fontSize(12)
          .fontColor(this.testResultMessage.indexOf('失败') >= 0 ? AppColors.destructive : AppColors.success)
          .margin({ bottom: 10 })
          .width('100%')
          .lineHeight(18)
      }

      // 模型名称 + 获取模型列表
      Row() {
        Column() {
          Text('模型名称')
            .fontSize(13)
            .fontColor(AppColors.textSecondary)
            .width('100%')
            .margin({ bottom: 4 })

          TextInput({ placeholder: 'deepseek-chat', text: this.editModelInput })
            .onChange((v: string) => {
              this.editModelInput = v
            })
            .width('100%')
            .height(40)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(8)
            .fontSize(14)
            .padding({ left: 12, right: 12 })
        }
        .layoutWeight(1)

        Text(this.fetchingModels ? '获取中...' : '获取模型列表')
          .fontSize(12)
          .fontColor(this.fetchingModels ? AppColors.textTertiary : AppColors.primary)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .margin({ left: 8, top: 18 })
          .border({
            width: 1,
            color: this.fetchingModels ? AppColors.textTertiary : AppColors.primary,
            style: BorderStyle.Solid
          })
          .borderRadius(6)
          .onClick(() => {
            this.fetchModels()
          })
      }
      .width('100%')
      .margin({ bottom: 4 })

      // 模型标签云
      if (this.fetchedModels.length > 0) {
        Row() {
          ForEach(this.fetchedModels, (model: string) => {
            Text(model)
              .fontSize(12)
              .fontColor(this.editModelInput === model ? AppColors.white : AppColors.primary)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(this.editModelInput === model ? AppColors.primary : AppColors.primaryLight)
              .borderRadius(12)
              .margin({ right: 6, bottom: 4 })
              .onClick(() => {
                this.selectModel(model)
              })
          }, (model: string): string => model)
        }
        .width('100%')
        .margin({ bottom: 12 })
      }

      // 操作按钮
      Row() {
        Text('取消')
          .fontSize(14)
          .fontColor(AppColors.textSecondary)
          .layoutWeight(1)
          .height(38)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.collapseCard()
          })

        Text('保存')
          .fontSize(14)
          .fontColor(AppColors.white)
          .layoutWeight(1)
          .height(38)
          .textAlign(TextAlign.Center)
          .backgroundColor(AppColors.primary)
          .borderRadius(10)
          .onClick(() => {
            this.saveProfile()
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  /** 新建方案卡片（含预设芯片） */
  @Builder
  NewProfileCard() {
    Column() {
      // 头部
      Row() {
        Column() {
          Text(this.editNameInput.length > 0 ? this.editNameInput : '新建方案')
            .fontSize(15)
            .fontColor(AppColors.textPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)

          if (this.editEndpointInput.length > 0) {
            Text(this.editEndpointInput)
              .fontSize(11)
              .fontColor(AppColors.textTertiary)
              .margin({ top: 2 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .onClick(() => {
          // 新建卡片也可以折叠
          this.collapseCard()
        })

        Text('放弃')
          .fontSize(12)
          .fontColor(AppColors.textTertiary)
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
          .onClick(() => {
            this.doCollapse()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 12, bottom: 4 })

      Divider().color(AppColors.separator).width('100%').margin({ bottom: 4 })

      // 展开体
      Column() {
        // 预设芯片 — 仅在新建时出现
        this.PresetChips()

        // 表单字段（复用 ProfileCardBody 的结构）
        Column() {
          Text('方案名称')
            .fontSize(13)
            .fontColor(AppColors.textSecondary)
            .width('100%')
            .margin({ bottom: 4 })

          TextInput({ placeholder: '为这个方案起个名字', text: this.editNameInput })
            .onChange((v: string) => {
              this.editNameInput = v
            })
            .width('100%')
            .height(40)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(8)
            .fontSize(14)
            .padding({ left: 12, right: 12 })
        }
        .width('100%')
        .margin({ bottom: 10 })

        Column() {
          Text('服务地址')
            .fontSize(13)
            .fontColor(AppColors.textSecondary)
            .width('100%')
            .margin({ bottom: 4 })

          TextInput({ placeholder: 'https://api.deepseek.com/v1', text: this.editEndpointInput })
            .onChange((v: string) => {
              this.editEndpointInput = v
            })
            .width('100%')
            .height(40)
            .backgroundColor(AppColors.bgSecondary)
            .borderRadius(8)
            .fontSize(14)
            .padding({ left: 12, right: 12 })
        }
        .width('100%')
        .margin({ bottom: 10 })

        // API 密钥 + 测试
        Row() {
          Column() {
            Text('API 密钥')
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .width('100%')
              .margin({ bottom: 4 })

            TextInput({ placeholder: 'sk-...', text: this.editApiKeyInput })
              .type(InputType.Password)
              .onChange((v: string) => {
                this.editApiKeyInput = v
              })
              .width('100%')
              .height(40)
              .backgroundColor(AppColors.bgSecondary)
              .borderRadius(8)
              .fontSize(14)
              .padding({ left: 12, right: 12 })
          }
          .layoutWeight(1)

          Text(this.testing ? '测试中...' : '测试连接')
            .fontSize(12)
            .fontColor(this.testing ? AppColors.textTertiary : AppColors.primary)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .margin({ left: 8, top: 18 })
            .border({
              width: 1,
              color: this.testing ? AppColors.textTertiary : AppColors.primary,
              style: BorderStyle.Solid
            })
            .borderRadius(6)
            .onClick(() => {
              this.doTestConnection()
            })
        }
        .width('100%')
        .margin({ bottom: 4 })

        if (this.testResultMessage.length > 0) {
          Text(this.testResultMessage)
            .fontSize(12)
            .fontColor(this.testResultMessage.indexOf('失败') >= 0 ? AppColors.destructive : AppColors.success)
            .margin({ bottom: 10 })
            .width('100%')
            .lineHeight(18)
        }

        // 模型名 + 获取模型
        Row() {
          Column() {
            Text('模型名称')
              .fontSize(13)
              .fontColor(AppColors.textSecondary)
              .width('100%')
              .margin({ bottom: 4 })

            TextInput({ placeholder: 'deepseek-chat', text: this.editModelInput })
              .onChange((v: string) => {
                this.editModelInput = v
              })
              .width('100%')
              .height(40)
              .backgroundColor(AppColors.bgSecondary)
              .borderRadius(8)
              .fontSize(14)
              .padding({ left: 12, right: 12 })
          }
          .layoutWeight(1)

          Text(this.fetchingModels ? '获取中...' : '获取模型列表')
            .fontSize(12)
            .fontColor(this.fetchingModels ? AppColors.textTertiary : AppColors.primary)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .margin({ left: 8, top: 18 })
            .border({
              width: 1,
              color: this.fetchingModels ? AppColors.textTertiary : AppColors.primary,
              style: BorderStyle.Solid
            })
            .borderRadius(6)
            .onClick(() => {
              this.fetchModels()
            })
        }
        .width('100%')
        .margin({ bottom: 4 })

        if (this.fetchedModels.length > 0) {
          Row() {
            ForEach(this.fetchedModels, (model: string) => {
              Text(model)
                .fontSize(12)
                .fontColor(this.editModelInput === model ? AppColors.white : AppColors.primary)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor(this.editModelInput === model ? AppColors.primary : AppColors.primaryLight)
                .borderRadius(12)
                .margin({ right: 6, bottom: 4 })
                .onClick(() => {
                  this.selectModel(model)
                })
            }, (model: string): string => model)
          }
          .width('100%')
          .margin({ bottom: 12 })
        }

        // 保存按钮
        Row() {
          Text('取消')
            .fontSize(14)
            .fontColor(AppColors.textSecondary)
            .layoutWeight(1)
            .height(38)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.collapseCard()
            })

          Text('保存')
            .fontSize(14)
            .fontColor(AppColors.white)
            .layoutWeight(1)
            .height(38)
            .textAlign(TextAlign.Center)
            .backgroundColor(AppColors.primary)
            .borderRadius(10)
            .onClick(() => {
              this.saveProfile()
            })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('92%')
    .backgroundColor(AppColors.bgTertiary)
    .borderRadius(12)
    .margin({ top: 8 })
  }

  @Builder
  PresetChips() {
    Row() {
      ForEach(PROVIDER_PRESETS, (preset: AiProviderPreset) => {
        Text(preset.name)
          .fontSize(11)
          .fontColor(AppColors.primary)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(AppColors.primaryLight)
          .borderRadius(10)
          .margin({ right: 6 })
          .onClick(() => {
            this.applyPreset(preset)
          })
      }, (preset: AiProviderPreset): string => preset.id)
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder
  AddButton() {
    Row() {
      Text('+ 添加 AI 服务')
        .fontSize(15)
        .fontColor(AppColors.primary)
        .fontWeight(FontWeight.Medium)
    }
    .width('92%')
    .height(44)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColors.bgTertiary)
    .borderRadius(12)
    .margin({ top: 8 })
    .onClick(() => {
      if (this.hasUnsavedEdit()) {
        this.showDiscardConfirm((): void => {
          this.showProviderPresetPicker()
        })
        return
      }
      this.showProviderPresetPicker()
    })
  }

  @Builder
  EmptyHint() {
    Column() {
      Text('🤖')
        .fontSize(36)

      Text('还没有自定义 AI 配置')
        .fontSize(15)
        .fontColor(AppColors.textPrimary)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 10 })

      Text('添加 DeepSeek、智谱GLM 等 AI 服务，\n让帖子总结和用户分析更快更智能')
        .fontSize(12)
        .fontColor(AppColors.textTertiary)
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })
        .lineHeight(18)
    }
    .width('92%')
    .padding({ top: 28, bottom: 8 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  HelpEntry() {
    Row() {
      Text('? AI 配置帮助')
        .fontSize(14)
        .fontColor(AppColors.textTertiary)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 12 })
    .onClick(() => {
      this.showGuide()
    })
  }
}
