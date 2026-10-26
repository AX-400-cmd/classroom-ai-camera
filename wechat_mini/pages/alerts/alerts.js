const api = require('../../utils/api.js');

const DETAIL_TEXT = { phone: '玩手机', sleep: '打瞌睡', attention: '注意力不集中' };

function fmtTime(ts) {
  const d = new Date(Number(ts) * 1000);
  const p = (n) => (n < 10 ? '0' + n : String(n));
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

Page({
  data: {
    alerts: [],
    err: '',
    wx: null,
    wxErr: '',
    openid: '',
    subscribing: false,
    base: '',
  },

  _timer: null,

  onShow() {
    if (typeof this.getTabBar === 'function' && this.getTabBar()) {
      this.getTabBar().setData({ selected: 2 });
    }
    this.setData({ base: api.getBase(), openid: getApp().globalData.openid || '' });
    this.refresh();
    this.fetchWxStatus();
    this.stopTimer();
    this._timer = setInterval(() => this.refresh(), 5000);
  },

  onHide() {
    this.stopTimer();
  },

  onUnload() {
    this.stopTimer();
  },

  stopTimer() {
    if (this._timer) clearInterval(this._timer);
    this._timer = null;
  },

  refresh() {
    api.fetchAlerts('')
      .then((data) => {
        const list = (data && data.alerts ? data.alerts : []).map((a) => ({
          id: a.id,
          detail: DETAIL_TEXT[a.detail] || DETAIL_TEXT[a.kind] || '注意力不集中',
          time: fmtTime(a.ts),
          seconds: Math.round(a.seconds || 0),
          score: a.score || 0,
          snapshot: a.snapshot_url ? api.getBase() + a.snapshot_url : '',
        }));
        list.reverse();
        this.setData({ alerts: list, err: '' });
      })
      .catch((error) => {
        this.setData({ err: error.message || '获取告警失败' });
      });
  },

  fetchWxStatus() {
    api.wxStatus()
      .then((data) => this.setData({ wx: data, wxErr: '' }))
      .catch((error) => this.setData({ wxErr: error.message || '无法获取推送状态' }));
  },

  /** 订阅消息授权：必须在 tap 回调里同步调起，不能放到 Promise 链之后。 */
  onSubscribe() {
    const wxInfo = this.data.wx || {};
    if (!wxInfo.configured) {
      wx.showModal({
        title: '后端未配置微信推送',
        content: '请在电脑端 wechat.json 里填好 appid / secret / template_id，并重启服务',
        showCancel: false,
      });
      return;
    }
    this.setData({ subscribing: true });
    wx.requestSubscribeMessage({
      tmplIds: [wxInfo.template_id],
      success: (res) => {
        const state = res[wxInfo.template_id];
        if (state !== 'accept') {
          wx.showToast({ title: '未授权，收不到推送', icon: 'none' });
          this.setData({ subscribing: false });
          return;
        }
        getApp()
          .ensureOpenid()
          .then((openid) => api.wxSubscribe(openid, 1))
          .then((res2) => {
            this.setData({ openid: res2.openid || '' });
            wx.showToast({ title: `已开启，剩余额度 ${res2.quota} 条`, icon: 'none' });
            this.fetchWxStatus();
          })
          .catch((error) => {
            wx.showToast({ title: error.message || '订阅失败', icon: 'none' });
          })
          .then(() => this.setData({ subscribing: false }));
      },
      fail: (err) => {
        this.setData({ subscribing: false });
        wx.showToast({
          title: (err && err.errMsg) || '授权失败',
          icon: 'none',
        });
      },
    });
  },

  onUnsubscribe() {
    const openid = this.data.openid || getApp().globalData.openid;
    if (!openid) {
      wx.showToast({ title: '尚未登录', icon: 'none' });
      return;
    }
    api.wxUnbind(openid)
      .then(() => {
        wx.showToast({ title: '已取消订阅', icon: 'none' });
        this.fetchWxStatus();
      })
      .catch((error) => wx.showToast({ title: error.message || '操作失败', icon: 'none' }));
  },

  onTestPush() {
    api.wxTest()
      .then((res) => wx.showToast({ title: (res && res.message) || '已发送', icon: 'none' }))
      .catch((error) => wx.showToast({ title: error.message || '发送失败', icon: 'none' }));
  },

  onTestAlert() {
    api.testAlert('phone')
      .then(() => {
        wx.showToast({ title: '已生成测试告警', icon: 'none' });
        setTimeout(() => this.refresh(), 800);
      })
      .catch((error) => wx.showToast({ title: error.message || '失败', icon: 'none' }));
  },

  onClear() {
    wx.showModal({
      title: '清空告警',
      content: '会清空服务端的告警列表，确认继续？',
      success: (res) => {
        if (!res.confirm) return;
        api.clearAlerts()
          .then(() => {
            this.setData({ alerts: [] });
            wx.showToast({ title: '已清空', icon: 'none' });
          })
          .catch((error) => wx.showToast({ title: error.message || '失败', icon: 'none' }));
      },
    });
  },

  previewImage(e) {
    const url = e.currentTarget.dataset.url;
    if (url) wx.previewImage({ urls: [url], current: url });
  },
});
