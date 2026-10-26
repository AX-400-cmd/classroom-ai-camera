const api = require('../../utils/api.js');

function fmtSize(bytes) {
  const n = Number(bytes) || 0;
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

Page({
  data: {
    files: [],
    err: '',
    kind: 'all',
    loading: false,
  },

  onShow() {
    if (typeof this.getTabBar === 'function' && this.getTabBar()) {
      this.getTabBar().setData({ selected: 1 });
    }
    this.refresh();
  },

  onPullDownRefresh() {
    this.refresh(() => wx.stopPullDownRefresh());
  },

  refresh(done) {
    api.fetchFiles(this.data.kind)
      .then((data) => {
        const files = (data && data.files ? data.files : []).map((f) => ({
          name: f.name,
          kind: f.kind,
          sizeText: fmtSize(f.size),
          modified: f.modified || '',
          recording: !!f.recording,
          thumb: f.kind === 'video'
            ? (f.poster ? api.getBase() + f.poster : '')
            : api.getBase() + f.url,
          url: api.getBase() + f.url,
        }));
        this.setData({ files, err: '' });
      })
      .catch((error) => this.setData({ err: error.message || '获取文件失败' }))
      .then(() => { if (done) done(); });
  },

  switchKind(e) {
    this.setData({ kind: e.currentTarget.dataset.kind }, () => this.refresh());
  },

  onOpen(e) {
    const { url, kind, thumb } = e.currentTarget.dataset;
    if (kind === 'video') {
      wx.previewMedia({ sources: [{ url, type: 'video', poster: thumb }] });
    } else {
      wx.previewImage({ urls: [url], current: url });
    }
  },

  onSave(e) {
    const { url, kind } = e.currentTarget.dataset;
    this.setData({ loading: true });
    wx.downloadFile({
      url,
      success: (res) => {
        if (res.statusCode !== 200) {
          wx.showToast({ title: '下载失败', icon: 'none' });
          return;
        }
        const save = kind === 'video' ? wx.saveVideoToPhotosAlbum : wx.saveImageToPhotosAlbum;
        save({
          filePath: res.tempFilePath,
          success: () => wx.showToast({ title: '已保存到相册' }),
          fail: (err) => {
            const msg = (err && err.errMsg) || '';
            wx.showToast({
              title: msg.indexOf('auth deny') >= 0 || msg.indexOf('authorize') >= 0
                ? '需要相册权限' : '保存失败',
              icon: 'none',
            });
          },
        });
      },
      fail: () => wx.showToast({ title: '下载失败，检查域名是否已配置', icon: 'none' }),
      complete: () => this.setData({ loading: false }),
    });
  },

  onDelete(e) {
    const { name } = e.currentTarget.dataset;
    wx.showModal({
      title: '删除文件',
      content: `确认删除「${name}」？此操作不可恢复。`,
      success: (res) => {
        if (!res.confirm) return;
        api.deleteFile(name)
          .then((data) => {
            wx.showToast({ title: (data && data.message) || '已删除', icon: 'none' });
            this.refresh();
          })
          .catch((error) => wx.showToast({ title: error.message || '删除失败', icon: 'none' }));
      },
    });
  },
});
