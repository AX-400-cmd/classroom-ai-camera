const api = require('../../utils/api.js');
const { DEFAULT_BASE } = require('../../config.js');

Page({
  data: {
    base: '',
    input: '',
    token: '',
    tokenInput: '',
    testing: false,
    result: '',
    resultOk: false,
    defaultBase: DEFAULT_BASE,
  },

  onShow() {
    const base = api.getBase();
    const token = api.getToken();
    this.setData({ base, input: base, token, tokenInput: token });
  },

  onInput(e) {
    this.setData({ input: e.detail.value });
  },

  onTokenInput(e) {
    this.setData({ tokenInput: e.detail.value });
  },

  onSaveToken() {
    const token = api.setToken(this.data.tokenInput);
    this.setData({ token });
    wx.showToast({ title: token ? '令牌已保存' : '已清空令牌', icon: 'none' });
  },

  onSave() {
    const value = String(this.data.input || '').trim();
    if (!value) {
      wx.showToast({ title: '地址不能为空', icon: 'none' });
      return;
    }
    if (value.indexOf('http') !== 0) {
      wx.showToast({ title: '必须以 https:// 开头', icon: 'none' });
      return;
    }
    if (value.indexOf('http://') === 0) {
      wx.showModal({
        title: '小程序要求 HTTPS',
        content: '正式版/体验版只能用 https 域名；http 仅开发者工具勾选「不校验合法域名」时可用。仍要保存？',
        success: (res) => { if (res.confirm) this.doSave(value); },
      });
      return;
    }
    this.doSave(value);
  },

  doSave(value) {
    const base = api.setBase(value);
    this.setData({ base });
    wx.showToast({ title: '已保存' });
  },

  onTest() {
    this.setData({ testing: true, result: '' });
    api.fetchStatus()
      .then((status) => {
        this.setData({
          resultOk: true,
          result: `连接成功：画面 ${status.frame_width}x${status.frame_height}，` +
            `人数 ${status.behavior_persons || 0}，` +
            `检测 ${status.behavior_enabled ? (status.behavior_running ? '运行中' : '已停止') : '未启用'}`,
        });
      })
      .catch((error) => {
        this.setData({ resultOk: false, result: error.message || '连接失败' });
      })
      .then(() => this.setData({ testing: false }));
  },

  onReset() {
    this.setData({ input: DEFAULT_BASE }, () => this.doSave(DEFAULT_BASE));
  },

  onCopyDomain() {
    wx.setClipboardData({ data: api.getBase() });
  },
});
