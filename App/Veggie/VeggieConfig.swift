import Foundation

// 蔬菜家族共用元素（規格：《蔬菜家族 App 共用基本元素規格》2026-11-14）。
// 從豆鍵的 App/Veggie/ 複製過來改的。還沒有獨立的 VeggieKit 套件；要搬成套件時只帶走這個資料夾，
// 每個 app 改的只有下面的 VeggieConfig.current。顏色、字級用的是蒜日子自己的 Theme 與 DT。

/// 每個 app 一份的設定檔。值是 nil 的那一列在設定頁整列隱藏
struct VeggieConfig {
    let name: String
    let slug: String
    let tagline: String
    /// App Store Connect → App 資訊 → Apple ID（一串數字）。填了才出現評分、分享
    let appStoreID: String?
    /// 意見回饋的收件信箱（全系列共用一個）。填了才出現意見回饋
    let supportEmail: String?
    /// 隱私權政策網頁（要跟 App Store Connect 填的同一頁）。nil 時那一列隱藏
    let privacyURL: URL?
    /// 設定頁最下面的連結（網站、FB、IG），照順序排
    let links: [VeggieLink]

    var appStoreURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)") }
    }

    var writeReviewURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }

    /// 「1.0.0」。讀不到是空字串
    var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// 「蒜日子 1.0.0 (34)」
    var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(name) \(version) (\(build))"
    }
}

extension VeggieConfig {
    static let current = VeggieConfig(
        name: "蒜日子",
        slug: "suanrizi",
        tagline: "手機上看得清楚的月曆",
        // App Store Connect → App 資訊 → Apple ID（2026-11-19 使用者給的）
        appStoreID: "6835095023",
        // 2026-11-18 使用者決定用這個信箱（隱私權政策頁也公開同一個）
        supportEmail: "charlie@domyweb.org",
        // 2026-11-18 上線。App Store Connect 的隱私權政策網址填同一頁
        privacyURL: URL(string: "https://domyweb.org/tools/suanrizi/privacy/"),
        links: [
            VeggieLink(kind: .website, address: "https://domyweb.org/"),
            VeggieLink(kind: .facebook, address: "https://www.facebook.com/profile.php?id=61556891560581"),
            VeggieLink(kind: .instagram, address: "https://www.instagram.com/domyweb_fc/")
        ]
    )
}

/// 設定頁最下面的一顆連結鈕
struct VeggieLink: Identifiable {
    enum Kind {
        case website
        case facebook
        case instagram
    }

    let kind: Kind
    let address: String

    var id: String { address }

    var url: URL? { URL(string: address) }

    /// 給語音朗讀的名稱
    var label: String {
        switch kind {
        case .website: return "網站"
        case .facebook: return "Facebook"
        case .instagram: return "Instagram"
        }
    }
}

/// 蔬菜家族的其他 app。蒜日子不連網，只用這份內建清單（規格是讀網路上的 apps.json）。
/// 沒有 App Store ID 也沒有網頁的不顯示；一個都沒有時，設定頁整列隱藏
struct VeggieApp: Identifiable {
    let slug: String
    let name: String
    let tagline: String
    let appStoreID: String?
    let webURL: URL?

    var id: String { slug }

    var link: URL? {
        if let appStoreID {
            return URL(string: "https://apps.apple.com/app/id\(appStoreID)")
        }
        return webURL
    }

    static let family: [VeggieApp] = [
        VeggieApp(slug: "qieji", name: "茄記", tagline: "想到就記", appStoreID: "6829151838", webURL: nil),
        VeggieApp(slug: "doujian", name: "豆鍵", tagline: "字大鍵緊，少按錯的注音鍵盤", appStoreID: "6829152938", webURL: nil),
        VeggieApp(slug: "suanrizi", name: "蒜日子", tagline: "手機上看得清楚的月曆", appStoreID: "6835095023", webURL: nil)
    ]

    /// 設定頁要列出來的：有連結、而且不是自己
    static var others: [VeggieApp] {
        family.filter { $0.slug != VeggieConfig.current.slug && $0.link != nil }
    }
}

/// 共用文案庫：全系列同一個東西叫同一個名字
enum VeggieText {
    static let appearance = "外觀"
    static let appearanceSystem = "跟隨系統"
    static let appearanceLight = "淺色"
    static let appearanceDark = "深色"
    static let restore = "恢復購買"
    static let feedback = "意見回饋"
    static let rate = "在 App Store 給我們評分"
    static let share = "分享給朋友"
    static let family = "蔬菜家族的其他 app"
    static let privacy = "隱私權政策"
    static let diagnosticsCopied = "已複製版本資訊"
    static let madeBy = "Made by DOMYWEB"
}
