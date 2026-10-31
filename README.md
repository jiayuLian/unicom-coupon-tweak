# unicom-coupon-tweak

TrollStore 注入中国联通 App 的 dylib，让「本机交费券」能够用于给任意联通号交费
（绕过前端 `mobInfo.number != loginPhoneNo` 的 gate 与服务端本机校验）。

## 原理
dylib 注入后，在 App 启动早期 hook 两处：
1. **主进程原生请求**：hook `NSURLSession` 的 `dataTaskWithRequest:*` / `uploadTaskWithRequest:*` 系列，
   把查券(`getNineGrid.action`)和下单校验(`mobAppPayFeeCheck`/`mobAppPayFeeApply`) 请求体里的
   `commonBean.phoneNo` / `commonBean.cityCode` / `custom.currentPhoneNumberAes` 改写成目标号，
   使服务端看到的「本机号 == 充值号 == 目标号」。
2. **H5 交费页**：hook `WKWebViewConfiguration` 初始化，给所有 WebView 注入 JS，
   hook `fetch` / `XMLHttpRequest`，把出去的请求 URL 与 body 里的上述字段一并改写（覆盖 WKWebView 独立网络进程）。

所有 objc 符号（Foundation / libobjc）由目标 App 进程运行时提供，dylib 本身不链接任何系统库
（`-undefined dynamic_lookup`），因此可在 **Linux 上交叉编译**，无需 Mac。

## 一键打包（GitHub Actions，无需 Mac）
免费 GitHub 账号私有仓库没有 macOS runner，本工程改用 **ubuntu-latest + clang/lld 交叉编译**
aarch64-apple-ios 的 Mach-O dylib，再用自带 `ldid_python.py` 做 ad-hoc 伪签名（TrollStore 注入时也会自动再签一次）。

1. 进本仓库 **Actions → Build couponhook dylib → Run workflow**
2. 填：
   - `target_phone`：券要给哪个联通号交费（默认 `15629799900`）
   - `target_city`：该号归属地城市码（`724`=湖北 `110`=天津 `010`=北京 …）
   - `target_phone_aes`：目标号 AES 密文（可选；留空则只改 phoneNo/cityCode）
3. 跑完在 **Artifacts** 下载 `couponhook-dylib`（内含 `couponhook.dylib`）

## TrollStore 注入
1. 手机装好 TrollStore
2. 把下载的 `couponhook.dylib` 用 TrollStore 的「分享 / 注入」功能塞进中国联通 App
3. 杀掉联通 App 重开 → 打开交话费页 → 切到目标号看是否出现满减券

## 拿 AES 密文（仅当服务端还校验 currentPhoneNumberAes 时需要）
1. 手机：TrollStore 装 Frida
2. 本地 `pip install frida frida-tools pycryptodome`
3. 跑 `python3 frida_locate.py`，在 App 走一次本机交费流程，脚本打印 AES key/iv
4. 把 key/iv 填回 `frida_locate.py` 顶部，重跑脚本直接算出 `encrypt(目标号)` 的 hex
5. 重新打包时把该 hex 填进 `target_phone_aes`

## 本地交叉编译（Linux / GitHub runner 环境）
```bash
sudo apt-get install -y clang lld
make                                                            # 用默认常量
make TARGET_PHONE=15629799900 TARGET_CITY=724 TARGET_PHONE_AES=<hex>   # 自定义
python3 ldid_python.py couponhook.dylib                         # ad-hoc 伪签名
```
编译命令实质：
```
clang -target aarch64-apple-ios -miphoneos-version-min=14.0 \
      -fuse-ld=lld -dynamiclib -nostdlib -undefined dynamic_lookup \
      -ObjC -o couponhook.dylib couponhook.m rt_bridge.m
```

## 已知限制
- 若服务端硬性比对 `cookie.c_mobile`（登录号）与 `phoneNo`，dylib 改不了 cookie（改则掉登录），
  此路失效，需走 App 内「代付 / 为他人交费」流程并重新抓包分析。
- `currentPhoneNumberAes` 缺失时仅改 phoneNo/cityCode，服务端若校验 AES 则下单会失败（先留空验证，再补 AES）。
