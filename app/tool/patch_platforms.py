#!/usr/bin/env python3
"""Idempotently patch AndroidManifest.xml / Info.plist / build.gradle after `flutter create`."""
import re, pathlib, sys

root = pathlib.Path(__file__).resolve().parents[1]

# ---- Android manifest
m = root / "android/app/src/main/AndroidManifest.xml"
if m.exists():
    s = m.read_text()
    perms = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.VIBRATE",
    ]
    add = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in s)
    if add:
        s = s.replace("<application", add + "    <application", 1)
    if "com.google.firebase.messaging.default_notification_channel_id" not in s:
        s = s.replace(
            "</activity>",
            '</activity>\n        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="hinamichi_alerts"/>',
            1,
        )
    if 'android:label="hinamichi"' in s:
        s = s.replace('android:label="hinamichi"', 'android:label="ヒナミチ"')
    m.write_text(s)
    print("patched", m)

# ---- Android minSdk (Firebase needs >= 23) — Kotlin DSL or Groovy
for g in [root / "android/app/build.gradle.kts", root / "android/app/build.gradle"]:
    if g.exists():
        s = g.read_text()
        s2 = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", s)
        s2 = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", s2)
        if s2 != s:
            g.write_text(s2)
            print("patched", g)

# ---- iOS Info.plist
p = root / "ios/Runner/Info.plist"
if p.exists():
    s = p.read_text()
    entries = {
        "NSLocationWhenInUseUsageDescription": "災害時に現在地周辺の避難場所と安全な経路を案内するために使います。位置情報そのものは保存・共有しません。",
        "NSLocationAlwaysAndWhenInUseUsageDescription": "災害通知を受け取った際に、あなたに関係があるかを判断するために使います。",
        "NSPhotoLibraryUsageDescription": "プロフィールのアイコンに使う画像を選ぶためだけに使います。選んだ画像以外は読み取りません。",
    }
    for k, v in entries.items():
        if k not in s:
            s = s.replace("</dict>\n</plist>", f"\t<key>{k}</key>\n\t<string>{v}</string>\n</dict>\n</plist>")
    if "UIBackgroundModes" not in s:
        s = s.replace("</dict>\n</plist>", "\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>remote-notification</string>\n\t\t<string>location</string>\n\t</array>\n</dict>\n</plist>")
    elif "<string>location</string>" not in s:
        # 既に配列があるなら location だけ足す(フレンドへの位置共有に必要)
        s = s.replace("<key>UIBackgroundModes</key>\n\t<array>", "<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>location</string>", 1)
    if "CFBundleDisplayName" in s:
        s = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1ヒナミチ\2", s)
    p.write_text(s)
    print("patched", p)

print("done")
