# Zdrama iOS (Objective-C)

`ZdramaIOS/` is the Swift app. This directory is the Objective-C app: a static library `ZdramaCoreObjC` and a UIKit app `ZdramaObjC`. Display name is `视频短剧`.

```text
cd ZdramaIOSObjC
xcodegen generate
python3 scripts/write_schemes.py
xcodebuild -scheme ZdramaObjC -destination 'generic/platform=iOS' build
xcodebuild -scheme ZdramaCoreObjC -destination 'platform=iOS Simulator,name=iPhone 17' test
```

`xcodegen` 2.46 does not write shared schemes for this spec. `scripts/write_schemes.py` writes them after generation. The installed simulator is iPhone 17, not iPhone 16.
