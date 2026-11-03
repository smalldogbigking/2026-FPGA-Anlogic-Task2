# 安路视界 Android 3.0.2

安装 releases/Anlogic-Vision-v3.0.2.apk；包名cn.fpgavision.monitor，versionCode6，沿用原签名与连接偏好，可覆盖升级。配套电脑端是latest_plus_v3_fixed/pc_bs v3.0.2，目标FPGA USB协议5。电脑保持运行，使用自行配置的服务器根网址。

原生监控、设备控制、视频播放及事件列表保留。模式13为智能分拣，编号3为原图备用。修复了连接校验仍要求旧V2软件标识的问题，现校验项目、服务标识、软件版本和协议5支持；原来保存的网址也受同样校验。SORT实时页显示阶段及四槽类别/数字，不将ACTIVE复用字段显示成人脸框。现有事件页可打开分拣工作台，扫描缩略图可回看。

原人脸视频仅成功保存后提醒；新增square_alert与sort_error允许系统通知，测试、录制中、失败视频不冒充保存。前台约2秒检查；后台JobScheduler可能约15分钟或更久，不是实时机械控制信号。没有新增常驻通知服务。

重建需要 Python、Android SDK Build Tools 36.0.0、Android API 36.1 和 JDK。配置 ANDROID_HOME 与 JAVA_HOME，再执行 .\build_apk.ps1，也可显式传入 -Sdk 和 -Jdk。脚本同步电脑网页资源，产物写入 android/releases。使用原签名升级时需在 android/signing 提供原密钥和口令文件，否则构建脚本生成本地签名。

已完成12项连接/协议/SORT兼容规则和原有通知规则检查、APK编译签名校验及网页资源对照；尚未安装到手机做本轮真机测试。电脑端若还运行3.0.0旧进程，应先关闭旧服务器，再从当前项目启动并重新连接COM口。

