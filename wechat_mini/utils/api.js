const { DEFAULT_BASE } = require('../config.js');

/** 读取当前服务地址（设置页改过就用改过的）。 */
function getBase() {
  return wx.getStorageSync('serverUrl') || DEFAULT_BASE || '';
}

function setBase(url) {
  const base = String(url || '').trim().replace(/\/+$/, '');
  wx.setStorageSync('serverUrl', base);
  return base;
}

/** 访问令牌（对应后端 --api-token / CLASSROOM_API_TOKEN）。没开鉴权就留空。 */
function getToken() {
  return wx.getStorageSync('apiToken') || '';
}

function setToken(token) {
  const value = String(token || '').trim();
  wx.setStorageSync('apiToken', value);
  return value;
}

/** 给 image / video 组件用的 URL 补令牌：这些组件没法带请求头，只能走 query。 */
function withToken(url) {
  const token = getToken();
  if (!token) return url;
  return `${url}${url.indexOf('?') >= 0 ? '&' : '?'}token=${encodeURIComponent(token)}`;
}

/** 统一把 wx.request 包成 Promise，并把失败翻译成人话。 */
function request(path, options = {}) {
  const base = getBase();
  if (!base || base.indexOf('your-domain') >= 0) {
    return Promise.reject(new Error('还没配置服务地址，请先到「设置」填写 HTTPS 域名'));
  }
  const { method = 'GET', data, timeout = 8000, header } = options;
  return new Promise((resolve, reject) => {
    wx.request({
      url: base + path,
      method,
      data: data || {},
      timeout,
      header: Object.assign(
        { 'content-type': 'application/json' },
        getToken() ? { Authorization: `Bearer ${getToken()}` } : {},
        header || {},
      ),
      success(res) {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(res.data);
          return;
        }
        const body = res.data && typeof res.data === 'object' ? res.data.message : '';
        reject(new Error(`服务返回 ${res.statusCode}${body ? '：' + body : ''}`));
      },
      fail(err) {
        const msg = (err && err.errMsg) || '';
        if (msg.indexOf('url not in domain list') >= 0) {
          reject(new Error('域名不在小程序合法域名列表里，请到微信公众平台配置 request 合法域名'));
        } else if (msg.indexOf('timeout') >= 0) {
          reject(new Error('请求超时，检查服务是否启动、域名是否可访问'));
        } else {
          reject(new Error('连接失败，检查服务是否启动、域名是否可访问'));
        }
      },
    });
  });
}

function get(path, params = {}) {
  const keys = Object.keys(params).filter((k) => params[k] !== '' && params[k] != null);
  const query = keys
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`)
    .join('&');
  return request(query ? `${path}?${query}` : path);
}

function post(path, data = {}) {
  return request(path, { method: 'POST', data });
}

module.exports = {
  getBase,
  setBase,
  getToken,
  setToken,
  withToken,
  request,
  get,
  post,
  // --- 业务接口 ---
  fetchStatus: () => get('/status'),
  fetchAlerts: (since = '') => get('/alerts', { since, limit: 100 }),
  fetchStats: (range = 'day') => get('/stats', { range }),
  fetchFiles: (kind = 'all') => get('/files', { kind }),
  startRecord: () => post('/start'),
  stopRecord: () => post('/stop'),
  snapshot: () => post('/snapshot'),
  deleteFile: (name) => post('/files/delete', { name }),
  clearAlerts: () => post('/alerts/clear'),
  testAlert: (kind = 'phone') => post('/alerts/test', { kind }),
  // --- 微信订阅消息 ---
  wxStatus: () => get('/wx/status'),
  wxLogin: (code) => post('/wx/login', { code }),
  wxSubscribe: (openid, count = 1) => post('/wx/subscribe', { openid, count }),
  wxUnbind: (openid) => post('/wx/unbind', { openid }),
  wxTest: () => post('/wx/test'),
  // --- 资源地址（给 image/video 组件用，走 downloadFile 合法域名）---
  frameUrl: (w) => withToken(`${getBase()}/frame.jpg${w ? '?w=' + w : ''}`),
  posterUrl: (name) =>
    withToken(`${getBase()}/files/poster?name=${encodeURIComponent(name)}`),
  fileUrl: (name) =>
    withToken(`${getBase()}/files/download?name=${encodeURIComponent(name)}`),
  snapshotUrl: (rel) => withToken(`${getBase()}${rel}`),
};
