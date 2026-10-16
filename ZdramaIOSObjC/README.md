# Zdrama iOS (Objective-C)

Pure Objective-C client. The Swift app stays in `ZdramaIOS/`.

```text
cd ZdramaIOSObjC
xcodegen generate
python3 scripts/write_schemes.py
xcodebuild -scheme ZdramaObjC -destination 'generic/platform=iOS' build
```

`xcodegen` 2.46 does not write shared schemes for this spec. `scripts/write_schemes.py` writes them after generation. Display name is `视频短剧`. The Swift app stays in `ZdramaIOS/`.
