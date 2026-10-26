# 打包成手机 APP（Android）

这个仓库里的 `flutter_app` 已经配置成可直接出 Android 包。本文只讲怎么构建、怎么装到手机、
以及手机连不上电脑时该查什么。

## 一、环境（本机已就绪）

| 组件 | 位置 | 状态 |
|---|---|---|
| Flutter SDK | `D:\Flutter\flutter` | 3.47.5 |
| Android SDK | `D:\Android` | platform-tools 37 / build-tools 36 / android-36、37 / NDK 28.2 |
| JDK | `D:\Android\Android Studio\jbr` | OpenJDK 25 |
| Gradle | 9.3.1（已在 `~/.gradle/wrapper/dists` 缓存） | 走腾讯镜像 |

`flutter_app/android/local.properties` 已写好 `sdk.dir` 与 `flutter.sdk`，换机器时要改。

> ⚠️ 项目路径 `D:\项目\...` 含中文，构建要过**两道关**：
>
> ① AGP 的非 ASCII 检查 —— 已在 `android/gradle.properties` 加 `android.overridePathCheck=true` 跳过；
> ② **Dart AOT 编译器（gen_snapshot）本身打不开中文路径下的 `app.dill`**，报
> `Error: Unable to read file ... app.dill` + `Dart snapshot generator failed with exit code 255`，
> 三个 ABI 全挂，**无法用配置绕过**（2026-09-29 实测踩坑）。
>
> **解决办法：用 `subst` 把项目映射成纯英文虚拟盘 X: 再构建（文件原地不动）：**
>
> ```powershell
> subst X: "D:\项目\Claw\ban"      # 重启电脑后映射失效，重新执行一次即可
> cd X:\flutter_app
> flutter pub get
> flutter build apk --release --split-per-abi
> ```
>
> 一键脚本 `build_android.bat` 已内置上述映射逻辑，双击即可。
> 彻底方案：把项目挪到纯英文目录（如 `D:\Claw\ban`），一劳永逸。

## 二、构建

> 直接在 `D:\项目\...` 原路径下构建会因中文路径在 AOT 阶段失败（见第一节的 ⚠️），
> 必须先映射虚拟盘。或者直接双击 `build_android.bat`，映射+构建一条龙。

```powershell
subst X: "D:\项目\Claw\ban"      # 重启后需重新执行
cd X:\flutter_app

# 调试包（体积大、可热重载，用于自己测试）
flutter build apk --debug

# 正式包（推荐：按 CPU 架构拆分，单包体积小一半以上）
flutter build apk --release --split-per-abi
```

产物位置：

| 命令 | 产物 |
|---|---|
| `--debug` | `build\app\outputs\flutter-apk\app-debug.apk` |
| `--split-per-abi` | `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`（现在绝大多数手机用这个） |

## 三、装到手机

**方式 A：USB 调试（推荐，改完代码秒级重装）**

1. 手机 `设置 → 关于手机` 连点「版本号」7 次打开开发者选项
2. `设置 → 开发者选项` 打开「USB 调试」
3. 数据线连接，手机上弹窗选「允许」
4. 验证连接：

```powershell
D:\Android\platform-tools\adb.exe devices
```

5. 安装并启动：

```powershell
subst X: "D:\项目\Claw\ban"      # 若尚未映射
cd X:\flutter_app
flutter run                      # 连接调试，支持热重载
flutter install                  # 只安装，不连调试
```

**方式 B：把 APK 传到手机直接安装**

微信/网盘/数据线把 APK 拷到手机，点开安装（需允许「安装未知来源应用」）。

**方式 C：无线 adb（不想插线）**

```powershell
D:\Android\platform-tools\adb.exe tcpip 5555
D:\Android\platform-tools\adb.exe connect 手机IP:5555
flutter install
```

## 四、手机端怎么用

1. 手机和电脑连**同一个 Wi-Fi**（同一网段，例如都是 192.168.3.x）
2. 打开 APP，地址填电脑局域网 IP：`http://192.168.3.3:8765`（不带端口会自动补 80，末尾多斜杠会自动去掉）
3. 点「连接」。地址会自动记住，下次启动直接连
4. 点画面选要跟踪的老师，底部按钮开始/停止录制、截图

**已连接时地址栏会自动收成一行**，点它可展开改地址；断线会自动展开。

## 五、连不上时按这个顺序查

| 现象 | 处理 |
|---|---|
| `Your project path contains non-ASCII characters` | 已通过 `android.overridePathCheck=true` 跳过 |
| `Unable to read file ... app.dill` / `AOT snapshotter exited with code 255` | **中文路径**：先 `subst X: "D:\项目\Claw\ban"`，再从 `X:\flutter_app` 构建（见第二节） |
| `Could not close incremental caches ... caches-jvm\jvm\kotlin` | Kotlin 增量编译缓存被锁（杀软实时扫描/残留守护进程）。已在 `gradle.properties` 加 `kotlin.incremental=false` 根治；重试前先停残留进程：`cd X:\flutter_app\android` 然后 `.\gradlew.bat --stop` |
| 构建特别慢（半小时以上） | 八成是 Defender 实时扫描拖慢 + 锁文件。**管理员 PowerShell** 执行：<br>`Add-MpPreference -ExclusionPath "D:\项目\Claw\ban"`<br>`Add-MpPreference -ExclusionPath "C:\Users\Administrator\.gradle"` |
| 提示「请求超时」 | 电脑上浏览器打开 `http://电脑IP:8765/status`，能打开说明服务正常，是手机和电脑不通 |
| 能打开 `/status` 但手机连不上 | **Windows 防火墙**挡了，放行 8765（见下方命令），或临时关闭对应网络的防火墙 |
| 电脑浏览器也打不开 | 服务没启动，运行 `py -3.12 -m classroom_camera.api_server --source 0 --host 0.0.0.0` |
| 提示「网络错误」且是 XML 相关 | 服务端 CORS 没生效，确认用的是最新版 `web.py` |

**放行防火墙（管理员 PowerShell）：**

```powershell
netsh advfirewall firewall add rule name="ClassroomCamera 8765" dir=in action=allow protocol=TCP localport=8765
```

> 手机 APP 走的是原生 HTTP，**不受浏览器同源策略限制**，比网页版少一层 CORS 麻烦；
> 后端已开启 `usesCleartextTraffic`，`http://` 明文地址可以直接用。

## 六、应用信息

| 项 | 值 |
|---|---|
| 应用名 | 智能课堂 |
| 包名 | `com.classroom.aicamera` |
| 版本 | `pubspec.yaml` 的 `version`，当前 `1.0.0+1` |
| 图标 | `android/app/src/main/res/`，Android 8+ 用自适应图标 |
| 常亮 | 预览页且已连接时保持屏幕常亮（`wakelock_plus`） |

改包名：`android/app/build.gradle.kts` 的 `namespace` 与 `applicationId`，
以及 `android/app/src/main/kotlin/` 下的目录结构，三处要一致。

## 七、正式发布前要做的事

1. **独立签名**：目前 release 用的是 debug 签名，能装不能用商店。正式分发需生成 keystore：

```powershell
keytool -genkey -v -keystore android/app/aicamera.jks -keyalg RSA -keysize 2048 -validity 10000 -alias aicamera
```

然后在 `android/key.properties` 写入密码，并在 `app/build.gradle.kts` 的 `buildTypes.release`
里替换 `signingConfig`。

2. **应用图标**：想换图标就重新生成 `res/` 下各密度 `ic_launcher.png` 与
   `drawable/ic_launcher_foreground.png`（108dp 画布，内容控制在中心 66dp 内）。

3. **版本号**：每次发新包把 `pubspec.yaml` 的 `version` 加一，例如 `1.0.0+1` → `1.0.1+2`。

## 八、已知限制

- 帧率约 4fps（MJPEG + 250ms 轮询），够看清课堂，不是直播级
- 录制编码用 H.264（`avc1`），手机播放器可直接播
- 手机端下载文件走系统浏览器（`url_launcher`），存在浏览器下载目录
- 没有鉴权，局域网内任何人知道 IP 都能看画面，正式使用建议加 token
