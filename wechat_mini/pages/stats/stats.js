const api = require('../../utils/api.js');

const RANGES = [
  { label: '今日', value: 'day' },
  { label: '近 7 天', value: 'week' },
  { label: '全部', value: 'all' },
];

Page({
  data: {
    range: 'day',
    ranges: RANGES,
    cards: [],
    hours: [],
    err: '',
    updated: '',
  },

  _timer: null,

  onShow() {
    if (typeof this.getTabBar === 'function' && this.getTabBar()) {
      this.getTabBar().setData({ selected: 3 });
    }
    this.refresh();
    this.stopTimer();
    this._timer = setInterval(() => this.refresh(), 15000);
  },

  onHide() { this.stopTimer(); },
  onUnload() { this.stopTimer(); },

  stopTimer() {
    if (this._timer) clearInterval(this._timer);
    this._timer = null;
  },

  onPullDownRefresh() {
    this.refresh(() => wx.stopPullDownRefresh());
  },

  switchRange(e) {
    this.setData({ range: e.currentTarget.dataset.value }, () => this.refresh());
  },

  refresh(done) {
    api.fetchStats(this.data.range)
      .then((data) => {
        const s = data && data.summary ? data.summary : {};
        const detail = s.by_detail || {};
        const byHour = s.by_hour || new Array(24).fill(0);
        const max = Math.max.apply(null, byHour.concat([1]));
        const hours = byHour.map((v, i) => ({
          h: i,
          v: v,
          pct: Math.round((v / max) * 100),
        }));
        this.setData({
          err: '',
          updated: new Date().toLocaleTimeString('zh-CN', { hour12: false }),
          hours,
          cards: [
            { label: '注意力不集中', value: String((detail.phone || 0) + (detail.sleep || 0)) },
            { label: '到课人数(峰值)', value: String(s.persons_max || 0) },
            { label: '最易分心时段', value: s.top_hour >= 0 ? `${s.top_hour}:00` : '-' },
          ],
        });
      })
      .catch((error) => this.setData({ err: error.message || '获取统计失败' }))
      .then(() => { if (done) done(); });
  },
});
