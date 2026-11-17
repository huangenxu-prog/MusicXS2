/*!
 * @name Huibq_lxmusic源
 * @description Github搜索“洛雪音乐音源”，禁止批量下载！
 * @version v1.2.0
 * @author Huibq
 */
const DEV_ENABLE = false
const API_URL = 'https://lxmusicapi.onrender.com'
const API_KEY = 'share-v3'
const MUSIC_QUALITY = {
  kw: ['128k', '320k'],
  kg: ['128k', '320k'],
  tx: ['128k', '320k'],
  wy: ['128k', '320k'],
  mg: ['128k', '320k'],
}
const MUSIC_SOURCE = Object.keys(MUSIC_QUALITY)
const { EVENT_NAMES, request, on, send, utils, env, version } = globalThis.lx
const httpFetch = (url, options = { method: 'GET' }) => {
  return new Promise((resolve, reject) => {
    request(url, options, (err, resp) => {
      if (err) return reject(err)
      resolve(resp)
    })
  })
}
const handleGetMusicUrl = async (source, musicInfo, quality) => {
  const songId = musicInfo.hash ?? musicInfo.songmid

  const request = await httpFetch(`${API_URL}/url/${source}/${songId}/${quality}`, {
    method: 'GET',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': `${env ? `lx-music-${env}/${version}` : `lx-usic-request/${version}`}`,
      'X-Request-Key': API_KEY,
    },
  })
  const status = Number(request?.statusCode || 0)
  let body = request?.body
  if (typeof body === 'string') {
    try { body = JSON.parse(body.trim()) } catch (_) {
      const preview = body.replace(/<[^>]*>/g, ' ').replace(/\\s+/g, ' ').trim().slice(0, 130)
      throw new Error(`Huibq响应不是JSON (HTTP ${status}): ${preview || '空响应'}`)
    }
  }
  if (!body || typeof body !== 'object' || body.code === undefined || body.code === null || !Number.isFinite(Number(body.code))) {
    const keys = body && typeof body === 'object' ? Object.keys(body).slice(0, 12).join(',') : 'none'
    throw new Error(`Huibq响应格式异常 (HTTP ${status}, keys=${keys})`)
  }
  const code = Number(body.code)
  switch (code) {
    case 0:
      if (typeof body.url !== 'string' || !body.url.startsWith('https://') && !body.url.startsWith('http://')) throw new Error('Huibq返回成功但缺少有效播放URL')
      return body.url
    case 1:
      throw new Error('block ip')
    case 2:
      throw new Error('get music url failed')
    case 4:
      throw new Error('internal server error')
    case 5:
      throw new Error('too many requests')
    case 6:
      throw new Error('param error')
    default:
      throw new Error(`Huibq接口错误 (HTTP ${status}, code=${code}): ${String(body.msg || '无错误说明').slice(0, 120)}`)
  }
}
const musicSources = {}
MUSIC_SOURCE.forEach(item => {
  musicSources[item] = {
    name: item,
    type: 'music',
    actions: ['musicUrl'],
    qualitys: MUSIC_QUALITY[item],
  }
})
on(EVENT_NAMES.request, ({ action, source, info }) => {
  switch (action) {
    case 'musicUrl':
      if (env != 'mobile') {
        console.log(`Handle Action(musicUrl)`)
        console.log('source', source)
        console.log('quality', info.type)
        console.log('musicInfo', info.musicInfo)
        void 0
      } else {
        console.log(`Handle Action(musicUrl)`)
        console.log('source', source)
        console.log('quality', info.type)
        console.log('musicInfo', info.musicInfo)
      }
      return handleGetMusicUrl(source, info.musicInfo, info.type)
        .then(data => Promise.resolve(data))
        .catch(err => Promise.reject(err))
    default:
      console.error(`action(${action}) not support`)
      return Promise.reject('action not support')
  }
})
send(EVENT_NAMES.inited, { status: true, openDevTools: DEV_ENABLE, sources: musicSources })
