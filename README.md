# unicom-coupon-tweak

TrollStore 注入中国联通 App (`com.chinaunicom.mobilebusiness`) 的 dylib，
让「本机券」能够用于给任意联通号交费（绕过前端 `mobInfo.number != loginPhoneNo` 的 gate）。

## 原理
- hook `WKWebView` 初始化，给交费页 H5 注入 JS
- 注入 JS hook `fetch` / `XMLHttpRequest`，把查券(`getNineGrid.action`)和下单校验(`mobAppPayFeeCheck`/`mobAppPayFeeApply`)
  请求里的 `commonBean.phoneNo` / `commonBean.cityCode` / `custom.currentPhoneNumberAes`
  改写成目标号，使服务端看到的「本机号 == 充值号 == 目标号」

## 一键打包（GitHub Actions，无需 Mac）
1. 进本仓库 **Actions → Build couponhook dylib → Run workflow**
2. 填：
   - `target_phone`：券要给哪个联通号交费（默认 `15629799900`）
   - `target_city`：该号归属地城市码（`724`=湖北 `110`=天津 `010`=北京 …）
   - `target_phone_aes`：目标号 AES 密文（可选，见下文「拿 AES 密文」；留空则只改 phoneNo/cityCode）
3. 跑完在 **Artifacts** 下载 `couponhook-dylib`（内含 `couponhook.dylib`）

## TrollStore 注入
1. 手机装好 TrollStore + 巨魔
2. 把下载的 `couponhook.dylib` 用 TrollStore 的「分享 / 注入」功能塞进中国联通 App
   （或本地 `bash build_inject.sh`，需要 Mac + ldid + insert_dylib）
3. 杀掉联通 App 重开 → 打开交话费页 → 切到目标号看是否出现满减券

## 拿 AES 密文（仅当服务端还校验 currentPhoneNumberAes 时需要）
1. 手机：TrollStore 装 Frida
2. Mac：`pip install frida frida-tools pycryptodome`
3. 跑 `python3 frida_locate.py`，在 App 走一次本机交费流程，脚本打印 AES key/iv
4. 把 key/iv 填回 `frida_locate.py` 顶部，重跑脚本直接算出 `encrypt(目标号)` 的 hex
5. 重新打包时把该 hex 填进 `target_phone_aes`

## 本地编译（有 Mac 时）
```bash
brew install ldid
make                                            # 用默认常量
make TARGET_PHONE=15629799900 TARGET_CITY=724 TARGET_PHONE_AES=<hex>   # 自定义
make sign
```

## 已知限制
- 若服务端硬性比对 `cookie.c_mobile`（登录号）与 `phoneNo`，dylib 改不了 cookie（改则掉登录），
  此路失效，需走 App 内「代付 / 为他人交费」流程并重新抓包分析。
- `currentPhoneNumberAes` 缺失时仅改 phoneNo/cityCode，服务端若校验 AES 则下单会失败。
