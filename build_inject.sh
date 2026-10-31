#!/bin/bash
# build_inject.sh —— 编译 + 注入 中国联通 App (iOS / TrollStore)
# 在 macOS 上执行。需要: Xcode CLT, ldid, TrollStore 已装好
set -e

APP_BUNDLE="com.chinaunicom.mobilebusiness"
APP_PATH="/Applications/ChinaUnicom.app"   # TrollStore 装的 App 实际路径, 按你机器确认
DYLIB="couponhook.dylib"

echo "[1/4] 编译 dylib ..."
make clean && make

echo "[2/4] 用 entitlements 重签名 dylib ..."
ldid -S entitlements.plist "$DYLIB"

echo "[3/4] 把 dylib 拷进 App 的 Frameworks 并写入 LC_LOAD_DYLIB ..."
# 用 insert_dylib (brew install insert_dylib) 或 optool 修改主二进制
# 方式 A: insert_dylib (自动加 LC_LOAD_DYLIB)
insert_dylib --all-yes --strip-codesig \
  "$(pwd)/$DYLIB" \
  "$APP_PATH/ChinaUnicom" \
  "$APP_PATH/ChinaUnicom_patched" 2>/dev/null || true
mv "$APP_PATH/ChinaUnicom_patched" "$APP_PATH/ChinaUnicom"
# 把 dylib 放进 Frameworks 目录
cp "$DYLIB" "$APP_PATH/Frameworks/" 2>/dev/null || cp "$DYLIB" "$APP_PATH/"

echo "[4/4] 重签 App 主二进制 ..."
ldid -S "$APP_PATH/ChinaUnicom"

echo ""
echo "[*] 完成。重启联通 App (kill 后重开), 打开交话费页即可。"
echo "[*] 验证: 切到目标号后看是否出现满减券; 提交时抓包确认"
echo "      mobAppPayFeeCheck 里 commonBean.phoneNo == kTargetPhone 且"
echo "      custom.currentPhoneNumberAes == kTargetPhoneAes"
echo ""
echo "[!] 若服务端还比对 cookie 里的 c_mobile, 则需走代付流程并另测, 详看说明。"
