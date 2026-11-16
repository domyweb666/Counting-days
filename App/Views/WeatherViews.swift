import SwiftUI
import CalendarCore

/// 一天的天氣寫成一行：圖示加「多雲 · 22–28° · 降雨 40%」
struct WeatherLine: View {
    let forecast: DayForecast

    var body: some View {
        HStack(spacing: DT.Space.s1) {
            Image(systemName: forecast.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(WeatherRules.line(forecast))
                .dFont(DT.TypeScale.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.sub)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("天氣：" + WeatherRules.line(forecast))
    }
}

/// Apple 規定的來源標示：Apple Weather 標誌，加一個連到資料來源說明的連結。
/// 有顯示天氣的畫面都要放一個。
struct WeatherCreditLink: View {
    @Environment(\.colorScheme) private var colorScheme
    let credit: WeatherCredit

    /// 標誌的高度
    private let markHeight: CGFloat = 12

    var body: some View {
        Link(destination: credit.legalPage) {
            HStack(spacing: DT.Space.s2) {
                AsyncImage(url: colorScheme == .dark ? credit.markDark : credit.markLight) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    // 標誌要連網才拿得到。拿不到時用文字版：Apple 標誌的字元加 Weather
                    Text("\u{F8FF} Weather").dFont(DT.TypeScale.caption)
                }
                .frame(height: markHeight)
                Text("資料來源")
                    .dFont(DT.TypeScale.caption)
                    .underline()
            }
            .foregroundStyle(Theme.sub)
            .frame(minHeight: DT.Size.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("天氣資料來自 Apple 天氣，點了看資料來源")
    }
}
