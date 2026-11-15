import Foundation

/// 天氣用的縣市。使用者在設定裡選一個，存的是 `id`。
public struct WeatherCity: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    /// 22 個縣市，北到南、東部、離島
    public static let all: [WeatherCity] = [
        WeatherCity(id: "keelung", name: "基隆市"),
        WeatherCity(id: "taipei", name: "臺北市"),
        WeatherCity(id: "newtaipei", name: "新北市"),
        WeatherCity(id: "taoyuan", name: "桃園市"),
        WeatherCity(id: "hsinchu-city", name: "新竹市"),
        WeatherCity(id: "hsinchu-county", name: "新竹縣"),
        WeatherCity(id: "miaoli", name: "苗栗縣"),
        WeatherCity(id: "taichung", name: "臺中市"),
        WeatherCity(id: "changhua", name: "彰化縣"),
        WeatherCity(id: "nantou", name: "南投縣"),
        WeatherCity(id: "yunlin", name: "雲林縣"),
        WeatherCity(id: "chiayi-city", name: "嘉義市"),
        WeatherCity(id: "chiayi-county", name: "嘉義縣"),
        WeatherCity(id: "tainan", name: "臺南市"),
        WeatherCity(id: "kaohsiung", name: "高雄市"),
        WeatherCity(id: "pingtung", name: "屏東縣"),
        WeatherCity(id: "yilan", name: "宜蘭縣"),
        WeatherCity(id: "hualien", name: "花蓮縣"),
        WeatherCity(id: "taitung", name: "臺東縣"),
        WeatherCity(id: "penghu", name: "澎湖縣"),
        WeatherCity(id: "kinmen", name: "金門縣"),
        WeatherCity(id: "lienchiang", name: "連江縣")
    ]

    /// 存檔裡的識別碼不在清單上（沒選過，或資料壞了）就當成沒選
    public static func find(_ id: String?) -> WeatherCity? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
