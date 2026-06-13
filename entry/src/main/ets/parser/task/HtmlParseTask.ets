import { parseHtmlToRawJson } from '../HtmlThreadParser'

@Concurrent
function parseHtmlTask(html: string): Object {
  return parseHtmlToRawJson(html) as Object
}

export { parseHtmlTask }
