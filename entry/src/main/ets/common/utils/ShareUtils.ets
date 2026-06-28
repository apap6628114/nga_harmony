import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common, Context } from '@kit.AbilityKit';
import { getActiveDomain } from '../../service/NgaApi';
import { unescapeHtml } from './Utils';
import type { PostInfo } from '../../model/PostInfo';
import { Logger, DOMAIN_MANAGER, formatError } from './Logger'

const logger = new Logger(DOMAIN_MANAGER, 'ShareUtils')

export function shareThread(context: Context, tid: number, threadTitle: string): void {
  let builder: string = ''
  if (threadTitle.length > 0) {
    builder += '《' + threadTitle + '》'
  }
  builder += ' - 艾泽拉斯国家地理论坛\n'
  builder += getActiveDomain() + '/read.php?tid=' + tid
  builder += ' (分享自NGA)'

  let data: systemShare.SharedData = new systemShare.SharedData({
    utd: utd.UniformDataType.PLAIN_TEXT,
    content: builder
  })
  let controller: systemShare.ShareController = new systemShare.ShareController(data)
  controller.on('dismiss', () => {
    logger.verbose('[ShareUtils] share thread panel dismissed')
  })
  let ctx: common.UIAbilityContext = context as common.UIAbilityContext
  controller.show(ctx, {
    previewMode: systemShare.SharePreviewMode.DETAIL,
    selectionMode: systemShare.SelectionMode.SINGLE
  }).catch((err: Object) => {
    logger.error('%{public}s', '[ShareUtils] share thread failed: ' + formatError(err))
  })
}

export function sharePost(context: Context, post: PostInfo, threadTitle: string): void {
  let builder: string = ''
  builder += '作者: ' + post.author
  if (post.lou > 0) {
    builder += '  ' + post.lou + '楼'
  }
  builder += '\n'
  let content: string = ''
  if (post.subject.length > 0) {
    content = post.subject
  } else {
    content = post.content.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '')
  }
  content = unescapeHtml(content)
  if (content.length > 100) {
    content = content.slice(0, 100) + '...'
  }
  if (content.length > 0) {
    builder += content + '\n'
  }
  if (threadTitle.length > 0) {
    builder += '《' + threadTitle + '》'
  }
  builder += ' - 艾泽拉斯国家地理论坛\n'
  builder += getActiveDomain() + '/read.php?pid=' + post.pid + '&tid=' + post.tid
  builder += ' (分享自NGA)'

  let data: systemShare.SharedData = new systemShare.SharedData({
    utd: utd.UniformDataType.PLAIN_TEXT,
    content: builder
  })
  let controller: systemShare.ShareController = new systemShare.ShareController(data)
  controller.on('dismiss', () => {
    logger.verbose('[ShareUtils] share post panel dismissed')
  })
  let ctx: common.UIAbilityContext = context as common.UIAbilityContext
  controller.show(ctx, {
    previewMode: systemShare.SharePreviewMode.DETAIL,
    selectionMode: systemShare.SelectionMode.SINGLE
  }).catch((err: Object) => {
    logger.error('%{public}s', '[ShareUtils] share post failed: ' + formatError(err))
  })
}
