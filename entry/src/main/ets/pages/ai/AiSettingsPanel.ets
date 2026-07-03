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
  @State testSuccess: boolean = false
  @State testing: boolean = false
  @State fetchingModels: boolean = false
  @State fetchedModels: string[] = []
  private fetchModelsRequestId: number = 0
  private testConnectionRequestId: number = 0

  /** 是否正在新建方案 */
  private isNew(): boolean {
    return this.expandedProfileId === NEW_ID
  }

  // ============== Dialog Controllers ==============

  deleteConfirmController?: CustomDialogController
  providerPickerController?: CustomDialogController
  discardConfirmController?: CustomDialogController

  aboutToAppear(): void {
    this.syncProfiles()
  }

  aboutToDisappear(): void {
    this.deleteConfirmController = undefined
    this.providerPickerController = undefined
    this.discardConfirmController = undefined
  }

  // ============== Data Sync ==============

  private syncProfiles(): void {
    this.profiles = appStore.settings.aiProfiles
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
    this.invalidatePendingRequests()
    this.expandedProfileId = profileId
    this.testResultMessage = ''
    this.testSuccess = false
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
        this.editApiKeyInput = profile.apiKey
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
    this.invalidatePendingRequests()
    this.expandedProfileId = ''
    this.clearEditBuffers()
  }

  /** 使正在返回途中的异步结果失效 */
  private invalidatePendingRequests(): void {
    this.fetchModelsRequestId++
    this.testConnectionRequestId++
    this.fetchingModels = false
    this.testing = false
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
      this.editApiKeyInput !== profile.apiKey ||
      this.editModelInput !== profile.modelName
  }

  private clearEditBuffers(): void {
    this.editNameInput = ''
    this.editEndpointInput = ''
    this.editApiKeyInput = ''
    this.editModelInput = ''
    this.testResultMessage = ''
    this.testSuccess = false
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
      profile.apiKey = this.editApiKeyInput.trim()
      appStore.addAiProfile(profile)
      appStore.showToast('已添加并切换到 ' + profile.name)
      appStore.setActiveAiConfig(appStore.settings.aiProfiles.length - 1)
    } else {
      // 从旧配置继承高级参数，避免编辑保存后丢失 temperature 等字段
      const old: AiProviderProfile | null = this.findProfile(this.expandedProfileId)
      if (old) {
        profile.id = old.id
        profile.streaming = old.streaming
        profile.temperature = old.temperature
        profile.maxTokens = old.maxTokens
        profile.privacyConfirmed = old.privacyConfirmed
        profile.apiKey = this.editApiKeyInput.trim()
      } else {
        profile.id = this.expandedProfileId
        profile.apiKey = this.editApiKeyInput.trim()
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
          this.invalidatePendingRequests()
          const preset: AiProviderPreset = PROVIDER_PRESETS[v]
          this.editNameInput = preset.name
          this.editEndpointInput = preset.endpoint
          this.editApiKeyInput = ''
          this.editModelInput = ''
          this.testResultMessage = ''
          this.testSuccess = false
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
    this.editApiKeyInput = ''
    this.editModelInput = ''
    this.testResultMessage = ''
    this.testSuccess = false
    this.fetchedModels = []
    this.invalidatePendingRequests()
  }

  // ============== Model List ==============

  /**
   * 解析当前编辑场景下的 API Key。
   *
   * 当前表单为空时返回空字符串，避免用户清空密钥后仍使用旧密钥。
   *
   * @returns 有效的 API Key 字符串
   */
  private resolveApiKey(): string {
    return this.editApiKeyInput.trim()
  }

  async fetchModels(): Promise<void> {
    if (this.fetchingModels) {
      return
    }
    if (!this.editEndpointInput || this.editEndpointInput.trim().length === 0) {
      appStore.showToast('请先填写服务地址')
      return
    }

    const requestId: number = this.fetchModelsRequestId + 1
    const profileId: string = this.expandedProfileId
    const endpoint: string = this.editEndpointInput.trim()
    const apiKey: string = this.resolveApiKey()

    this.fetchModelsRequestId = requestId
    this.fetchingModels = true
    this.fetchedModels = []

    const tempProfile: AiProviderProfile = new AiProviderProfile()
    tempProfile.endpoint = endpoint
    tempProfile.apiKey = apiKey

    try {
      const models: string[] = await listModels(tempProfile)
      if (this.isCurrentFetchModelsRequest(requestId, profileId, endpoint, apiKey)) {
        this.fetchedModels = models
      }
      if (models.length === 0 && this.isCurrentFetchModelsRequest(requestId, profileId, endpoint, apiKey)) {
        appStore.showToast('未获取到模型列表，请手动输入')
      }
    } catch (e) {
      const err: Error = e as Error
      if (this.isCurrentFetchModelsRequest(requestId, profileId, endpoint, apiKey)) {
        appStore.showToast('获取模型列表失败：' + (err.message || '未知错误'))
      }
    } finally {
      if (this.fetchModelsRequestId === requestId) {
        this.fetchingModels = false
      }
    }
  }

  /**
   * 判断模型列表请求返回时是否仍属于当前编辑上下文。
   *
   * @param requestId - 请求序号
   * @param profileId - 发起请求时展开的配置 ID
   * @param endpoint - 发起请求时的端点
   * @param apiKey - 发起请求时的密钥
   * @returns 是否仍为当前请求
   */
  private isCurrentFetchModelsRequest(
    requestId: number,
    profileId: string,
    endpoint: string,
    apiKey: string
  ): boolean {
    return this.fetchModelsRequestId === requestId &&
      this.expandedProfileId === profileId &&
      this.editEndpointInput.trim() === endpoint &&
      this.resolveApiKey() === apiKey
  }

  selectModel(modelName: string): void {
    this.editModelInput = modelName
  }

  // ============== Connection Test ==============

  async doTestConnection(): Promise<void> {
    if (this.testing) {
      return
    }
    if (!this.editEndpointInput || this.editEndpointInput.trim().length === 0 ||
        !this.editModelInput || this.editModelInput.trim().length === 0) {
      appStore.showToast('请先填写服务地址和模型名称')
      return
    }

    const apiKey: string = this.resolveApiKey()
    if (apiKey.length === 0) {
      appStore.showToast('请先填写 API 密钥')
      return
    }

    const requestId: number = this.testConnectionRequestId + 1
    const profileId: string = this.expandedProfileId
    const endpoint: string = this.editEndpointInput.trim()
    const modelName: string = this.editModelInput.trim()

    this.testConnectionRequestId = requestId
    this.testing = true
    this.testResultMessage = ''

    const tempProfile: AiProviderProfile = new AiProviderProfile()
    tempProfile.endpoint = endpoint
    tempProfile.apiKey = apiKey
    tempProfile.modelName = modelName

    try {
      const result: AiTestResult = await testConnection(tempProfile)
      if (!this.isCurrentTestConnectionRequest(requestId, profileId, endpoint, apiKey, modelName)) {
        return
      }
      if (result.success) {
        this.testSuccess = true
        this.testResultMessage = '连接成功 · 耗时 ' + result.durationMs + 'ms\n' + result.message
      } else {
        this.testSuccess = false
        this.testResultMessage = '连接失败 · ' + result.errorMessage
      }
    } catch (e) {
      if (this.isCurrentTestConnectionRequest(requestId, profileId, endpoint, apiKey, modelName)) {
        this.testSuccess = false
        const err: Error = e as Error
        this.testResultMessage = '连接失败 · ' + (err.message || '未知错误')
      }
    } finally {
      if (this.testConnectionRequestId === requestId) {
        this.testing = false
      }
    }
  }

  /**
   * 判断测试连接请求返回时是否仍属于当前编辑上下文。
   *
   * @param requestId - 请求序号
   * @param profileId - 发起请求时展开的配置 ID
   * @param endpoint - 发起请求时的端点
   * @param apiKey - 发起请求时的密钥
   * @param modelName - 发起请求时的模型名
   * @returns 是否仍为当前请求
   */
  private isCurrentTestConnectionRequest(
    requestId: number,
    profileId: string,
    endpoint: string,
    apiKey: string,
    modelName: string
  ): boolean {
    return this.testConnectionRequestId === requestId &&
      this.expandedProfileId === profileId &&
      this.editEndpointInput.trim() === endpoint &&
      this.resolveApiKey() === apiKey &&
      this.editModelInput.trim() === modelName
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
        .fontColor(AppColors.destructive)
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .onClick(() => {
          this.deleteProfile(profile.id)
        })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 12, bottom: 12 })
  }

  /**
   * 公共表单字段 — 方案名称、服务地址、API 密钥、测试连接、
   * 模型名称、获取模型列表、模型标签云及保存/取消按钮。
   *
   * 由 ProfileCardBody 和 NewProfileCard 共享，
   * 避免两处各维护一份相同的表单代码。
   */
  @Builder
  ProfileFormFields() {
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
        .fontColor(this.testSuccess ? AppColors.success : AppColors.destructive)
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

  @Builder
  ProfileCardBody() {
    Column() {
      this.ProfileFormFields()
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
            this.collapseCard()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 12, bottom: 4 })

      Divider().color(AppColors.separator).width('100%').margin({ bottom: 4 })

      // 展开体
      Column() {
        // 预设芯片 — 仅在新建时出现
        this.PresetChips()

        this.ProfileFormFields()
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

}
