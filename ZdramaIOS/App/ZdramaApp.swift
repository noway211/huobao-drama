// ============================================================================
// 火宝短剧 iOS 应用入口
// ============================================================================
// 【README —— 如何在 Xcode 中打开本应用】
//
// 本仓库未提交 .xcodeproj（构建环境没有安装 xcodegen，无法生成；也不建议手写）。
// 工程配置的权威版本见 ZdramaIOS/project.yml：安装 xcodegen 后执行
//
//     cd ZdramaIOS && xcodegen generate
//
// 即可生成 Zdrama.xcodeproj 并直接打开运行。
//
// 如果不使用 xcodegen，请按以下步骤在 Xcode 中手动创建 App 工程并挂载本地包：
//
// 1. Xcode → File → New → Project... → iOS → App。
//    产品名填写 Zdrama，Interface 选 SwiftUI，Language 选 Swift，
//    存储位置选择本仓库根目录，取消勾选 "Create Git repository"（仓库已初始化）。
// 2. 删除新建工程自动生成的 ContentView.swift 及对应测试文件。
// 3. 将本 App/ 目录下的全部 Swift 文件（ZdramaApp.swift、AppContainer.swift、
//    RootView.swift、Features/ 等）拖入新建 Target 的 Compile Sources，
//    无需勾选 "Copy items if needed"（保持引用即可）。
// 4. 挂载本地包：File → Add Package Dependencies... → 点击左下角 "Add Local..."
//    → 选择 ZdramaIOS/ 目录（即 Package.swift 所在目录）→ Add Package。
//    随后在 Target 的 General → "Frameworks, Libraries, and Embedded Content"
//    中确认已加入 ZdramaCore（若未自动加入则手动添加）。
// 5. 将 App 与 ZdramaCore 两个 Target 的 Deployment Target 均设为 iOS 17.0，
//    Swift 版本设为 5.9（与 Package.swift 保持一致）。
// 6. 配置 Info.plist（xcodegen 会按 project.yml 的 info.properties 自动生成；
//    手工创建时需包含）：
//      - CFBundleDisplayName: 火宝短剧
//      - CFBundleIdentifier:  com.huobao.zdrama
//      - UILaunchScreen:     {}（空字典）
//      - NSAppTransportSecurity.NSAllowsLocalNetworking: true
// 7. 选择 Zdrama scheme 并运行。ZdramaCore 由本地 SPM 包编译链接，
//    其唯一外部依赖为 GRDB.swift（由 SPM 自动拉取）。
// ============================================================================
import SwiftUI
import ZdramaCore

@main
struct ZdramaApp: App {
    @StateObject private var container = AppContainer.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
