// 默认服务地址：部署到 HTTPS 域名后，把这里改成你的域名（不要带结尾斜杠）。
// 小程序里「设置」页也能改，改完存在本地，优先级高于此处。
const DEFAULT_BASE = 'https://your-domain.example';

// 抓帧轮询间隔（毫秒）。穿透带宽紧张可调到 1000。
const DEFAULT_FRAME_INTERVAL = 600;

module.exports = {
  DEFAULT_BASE,
  DEFAULT_FRAME_INTERVAL,
};
