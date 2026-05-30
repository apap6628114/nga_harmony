import { PostInfo } from '../service/NgaApi'
import type { MessageThreadInfo, MessageArticle } from '../model/Message'
import type { NotificationInfo } from '../model/Notification'
import type { BlacklistEntry } from '../store/AppStore'
import type { FavBoard } from '../store/AppStore'
import type { FilterKeyword } from '../model/FilterKeyword'
import type { UserNoteEntry } from '../model/NoteInfo'
import type { Category, BoardContent } from '../model/Forum'

class PostInfoDataSource implements IDataSource {
  private dataList: PostInfo[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): PostInfo {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: PostInfo[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  appendAll(list: PostInfo[]): void {
    const start: number = this.dataList.length
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
      this.notifyAdd(start + i)
    }
  }

  prependAll(list: PostInfo[]): void {
    this.dataList = list.concat(this.dataList)
    for (let i = 0; i < list.length; i++) {
      this.notifyAdd(i)
    }
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  updateAt(index: number, item: PostInfo): void {
    if (index < 0 || index >= this.dataList.length) {
      return
    }
    this.dataList[index] = item
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index)
    }
  }

  length(): number {
    return this.dataList.length
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }

  private notifyAdd(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index)
    }
  }
}

class ThreadDataSource implements IDataSource {
  private dataList: object[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): object {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: object[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  appendAll(list: object[]): void {
    const start: number = this.dataList.length
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
      this.notifyAdd(start + i)
    }
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  length(): number {
    return this.dataList.length
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }

  private notifyAdd(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index)
    }
  }
}

class MessageThreadDataSource implements IDataSource {
  private dataList: MessageThreadInfo[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): MessageThreadInfo {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: MessageThreadInfo[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

class MessageArticleDataSource implements IDataSource {
  private dataList: MessageArticle[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): MessageArticle {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: MessageArticle[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

class NotificationDataSource implements IDataSource {
  private dataList: NotificationInfo[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): NotificationInfo {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: NotificationInfo[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

class BlacklistDataSource implements IDataSource {
  private dataList: BlacklistEntry[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): BlacklistEntry {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: BlacklistEntry[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

interface SidebarBoardItem {
  fid: number;
  stid: number;
  name: string;
}

interface SidebarSection {
  id: string;
  name: string;
  items: SidebarBoardItem[];
  collapsed: boolean;
  collapsible: boolean;
}

class SidebarDataSource implements IDataSource {
  private dataList: SidebarSection[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): SidebarSection {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: SidebarSection[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  updateSection(index: number, section: SidebarSection): void {
    this.dataList[index] = section
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index)
    }
  }

  indexOf(sectionId: string): number {
    for (let i = 0; i < this.dataList.length; i++) {
      if (this.dataList[i].id === sectionId) {
        return i
      }
    }
    return -1
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

class CategoryDataSource implements IDataSource {
  private dataList: Category[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): Category {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: Category[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

class HistoryItemDataSource implements IDataSource {
  private dataList: object[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): object {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: object[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

class NotesDataSource implements IDataSource {
  private dataList: UserNoteEntry[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): UserNoteEntry {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: UserNoteEntry[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

class FilterKeywordDataSource implements IDataSource {
  private dataList: FilterKeyword[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.dataList.length
  }

  getData(index: number): FilterKeyword {
    return this.dataList[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(list: FilterKeyword[]): void {
    this.dataList = []
    for (let i = 0; i < list.length; i++) {
      this.dataList.push(list[i])
    }
    this.notifyReload()
  }

  clear(): void {
    this.dataList = []
    this.notifyReload()
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}

export {
  PostInfoDataSource, ThreadDataSource, MessageThreadDataSource,
  MessageArticleDataSource, NotificationDataSource, BlacklistDataSource,
  NotesDataSource, FilterKeywordDataSource, CategoryDataSource,
  HistoryItemDataSource, SidebarDataSource, SidebarSection, SidebarBoardItem
}
