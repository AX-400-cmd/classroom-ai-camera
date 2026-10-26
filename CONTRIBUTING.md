# 贡献指南

感谢你对「智能课堂 AI 摄像头系统」的关注与贡献！

## 开发流程

1. Fork 本仓库并 Clone 到本地。
2. 从 `main` 切出特性分支：`git checkout -b feat/your-feature`。
3. 提交改动，信息建议遵循 `feat/fix/docs/chore: 简述` 风格。
4. 推送到你的 Fork 并发起 Pull Request。

## 提交前注意

- **不要提交任何密钥或隐私数据**：
  - 微信配置请只提交 `wechat.example.json` 模板；真实 `wechat.json` 已写入 `.gitignore`。
  - 真实课堂录像、告警截图、统计数据库位于 `outputs/`，已被忽略，请勿加入提交。
  - 个人学术文档位于 `work/`，已被忽略。
- 后端密钥（如 `CLASSROOM_API_TOKEN`、微信 `WECHAT_APPID/SECRET`）一律走环境变量，不要硬编码。
- 提交前请确认 `git status` 中没有出现上述敏感文件。

## 代码风格

- Python：遵循 PEP 8，建议用 `ruff` / `flake8` 自检。
- Dart/Flutter：`flutter analyze` 应无 error / warning。
- 小程序：WXML/WXSS/JS 保持与现有结构一致。

## 行为准则

请友善、就事论事地交流。本项目以 [MIT License](./LICENSE) 开源，提交即表示你同意以相同许可证授权你的贡献。
