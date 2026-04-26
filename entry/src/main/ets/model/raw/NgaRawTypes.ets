export interface NgaRawThreadResponse {
  data: NgaRawThreadData
  encode: string
  time: number
}

export interface NgaRawThreadData {
  __R: Record<string, Object>
  __U: Record<string, Object>
  __T: Object
  __F: Record<string, string>
  __ROWS: number
  __R__ROWS_PAGE: number
  __PAGE: number
  __CU?: Object
  __REPUTATIONS?: Record<string, Object>
  __GLOBAL?: Record<string, string>
}

export interface NgaRawPost {
  pid: number
  fid: number
  tid: number
  lou: number
  authorid: number
  author: string
  subject: string
  content: string
  postdate: string
  postdatetimestamp: number
  type: number
  score: number
  score_2: number
  content_length: number
  from_client: string
  from_client_model: string
  vote: string
  alterinfo: string
  isanonymous: boolean
  attachs?: Record<string, Object>
  comment?: Record<string, Object>
  comment_id?: Record<string, number>
  comment_to_id?: number
  reply_to?: number
}

export interface NgaRawAttachment {
  attachurl: string
  size: number
  type: string
  subid: number
  url_utf8_org_name: string
  dscp: string
  path: string
  name: string
  ext: string
  thumb: number
}

export interface NgaRawUser {
  uid: number
  username: string
  credit: number
  medal: string
  reputation: string
  groupid: number
  memberid: number
  avatar: string
  yz: number
  site: string
  honor: string
  regdate: number
  mute_time: string
  postnum: number
  rvrc: number
  money: number
  thisvisit: number
  signature: string
  nickname: string
  bit_data: number
  group_bit_buf?: number
  buffs?: Record<string, Object>
  remark?: Record<string, Object>
  __GROUPS?: Record<string, NgaRawGroupEntry>
  __MEDALS?: Record<string, NgaRawMedalEntry>
}

export interface NgaRawGroupEntry {
  '0': string
  '1': number
  '2': number
}

export interface NgaRawMedalEntry {
  '0': string
  '1': string
  '2': string
  '3': number
}

export interface NgaRawThreadMeta {
  fid: number
  tid: number
  subject: string
  replies: number
  authorid: number
  author: string
  postdate: number
  lastpost: number
  lastposter: string
  locked: number
  recommend: number
  digest: number
  type: number
  topic_misc: string
  quote_from: number
  quote_to: string
  lastmodify: number
  tpid: number
  this_visit_rows: number
}

export interface NgaRawForumInfo {
  name: string
}

export interface NgaRawCurrentUser {
  uid: number
  group_bit: number
  admincheck: string
  rvrc: number
}
