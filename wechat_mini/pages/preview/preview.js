const api = require('../../utils/api.js');
const { DEFAULT_FRAME_INTERVAL } = require('../../config.js');

const INTERVALS = [
  { label: '流畅 0.6s', value: 600 },
  { label: '均衡 1s', value: 1000 },
  { label: '省流 2s', value: 2000 },
];

Page({
  data: {
    status: null,
    err: '',
    playing: true,
    interval: DEFAULT_FRAME_INTERVAL || 600,
    intervals: INTERVALS,
    bufA: '',
    bufB: '',
    active: 'A',
    loading: false,
  },

  _frameTimer: null,
  _statusTimer: null,

  onLoad() {
    const saved = wx.getStorageSync('frameInterval');
    if (saved) this.setData({ interval: Number(saved) });
  },

  onShow() {
    if (typeof this.getTabBar === 'function' && this.getTabBar()) {
      this.getTabBar().setData({ selected: 0 });
    }
    this.startLoops();
  },

  onHide() {
    this.stopLoops();
  },

  onUnload() {
    this.stopLoops();
  },

  startLoops() {
    this.stopLoops();
    this.fetchStatus();
    this.tickFrame();
    this._frameTimer = setInterval(() => this.tickFrame(), this.data.interval);
    this._statusTimer = setInterval(() => this.fetchStatus(), 2000);
  },

  stopLoops() {
    if (this._frameTimer) clearInterval(this._frameTimer);
    if (this._statusTimer) clearInterval(this._statusTimer);
    this._frameTimer = null;
    this._statusTimer = null;
  },

  /** 双缓冲抓帧：先给非当前层换 src，加载完成后再切换显示，避免闪白。 */
  tickFrame() {
    if (!this.data.playing) return;
    const url = `${api.frameUrl(640)}&t=${Date.now()}`;
    const next = this.data.active === 'A' ? 'B' : 'A';
    this.setData({ [next === 'A' ? 'bufA' : 'bufB']: url });
  },

  onBufLoad(e) {
    const buf = e.currentTarget.dataset.buf;
    if (this.data.active !== buf) {
      this.setData({ active: buf, err: '' });
    }
  },

  fetchStatus() {
    api.fetchStatus()
      .then((status) => {
        this.setData({ status, err: '' });
      })
      .catch((error) => {
        this.setData({ err: error.message || '无法连接服务' });
      });
  },

  togglePlay() {
    const playing = !this.data.playing;
    this.setData({ playing });
    if (playing) this.tickFrame();
  },

  switchInterval(e) {
    const value = Number(e.currentTarget.dataset.value);
    this.setData({ interval: value });
    wx.setStorageSync('frameInterval', value);
    this.startLoops();
  },

  onRecord() {
    const recording = this.data.status && this.data.status.recording;
    this.setData({ loading: true });
    const task = recording ? api.stopRecord() : api.startRecord();
    task
      .then((res) => {
        wx.showToast({ title: (res && res.message) || '已执行', icon: 'none' });
        this.fetchStatus();
      })
      .catch((error) => {
        wx.showToast({ title: error.message || '操作失败', icon: 'none' });
      })
      .then(() => this.setData({ loading: false }));
  },

  onSnapshot() {
    api.snapshot()
      .then((res) => wx.showToast({ title: (res && res.message) || '已截图', icon: 'none' }))
      .catch((error) => wx.showToast({ title: error.message || '截图失败', icon: 'none' }));
  },

  goSettings() {
    wx.navigateTo({ url: '/pages/settings/settings' });
  },
});
