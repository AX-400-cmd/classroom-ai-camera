Component({
  data: {
    selected: 0,
    list: [
      { path: '/pages/preview/preview', text: '实时预览' },
      { path: '/pages/files/files', text: '录制文件' },
      { path: '/pages/alerts/alerts', text: '行为告警' },
      { path: '/pages/stats/stats', text: '课堂统计' },
    ],
  },
  methods: {
    switchTab(e) {
      const { path } = e.currentTarget.dataset;
      wx.switchTab({ url: path });
    },
  },
});
