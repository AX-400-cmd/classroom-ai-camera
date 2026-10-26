const api = require('./utils/api.js');

App({
  globalData: {
    status: null,
    openid: '',
  },

  onLaunch() {
    this.globalData.openid = wx.getStorageSync('openid') || '';
  },

  /** 登录并缓存 openid（订阅消息推送需要）。 */
  ensureOpenid() {
    if (this.globalData.openid) {
      return Promise.resolve(this.globalData.openid);
    }
    return new Promise((resolve, reject) => {
      wx.login({
        success: (res) => {
          if (!res.code) {
            reject(new Error('wx.login 失败：' + (res.errMsg || '')));
            return;
          }
          api.wxLogin(res.code)
            .then((data) => {
              const openid = data && data.openid;
              if (!openid) {
                reject(new Error('后端未返回 openid，检查 wechat.json 的 appid/secret'));
                return;
              }
              this.globalData.openid = openid;
              wx.setStorageSync('openid', openid);
              resolve(openid);
            })
            .catch(reject);
        },
        fail: (err) => reject(new Error('wx.login 失败：' + (err.errMsg || ''))),
      });
    });
  },
});
