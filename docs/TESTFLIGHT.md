# 把蒜日子裝到 iPhone（TestFlight）

程式放在 GitHub，編譯、簽章、上傳都由 GitHub 的 macOS 機器做。你要做的是在 Apple 那邊建好 app、產生一組金鑰，然後把四個值貼進 GitHub。全部做一次就好，之後每次要更新只按一個按鈕。

這份流程還沒有用真的金鑰跑過。第一次跑如果失敗，把 Actions 頁面的錯誤訊息貼給 Claude。

## 一、在 Apple 建好 app

1. 到 [Apple Developer 的 Identifiers](https://developer.apple.com/account/resources/identifiers/list) 按「+」，選 App IDs → App，Bundle ID 選 Explicit，填 `com.domyweb.countingdays`。Capabilities 要勾 WeatherKit，旁邊的 App Services 分頁也要勾 WeatherKit（天氣用的，兩個都要；改完按 Save）。已經建好 App ID 的話，點進去補勾一樣可以。
   小工具另外要三步（2026-11-16 加，含小工具的版本上傳前要做完）：
   - 同一頁左上角的下拉選單改成 App Groups，按「+」，Description 隨便填（例如「蒜日子」），Identifier 填 `group.com.domyweb.countingdays`。
   - 下拉選單切回 App IDs，按「+」再建一個 App ID，Bundle ID 選 Explicit，填 `com.domyweb.countingdays.widget`。Capabilities 勾 App Groups，按旁邊的 Configure，選剛剛那個群組。
   - 點進原本的 `com.domyweb.countingdays`，一樣勾 App Groups、選同一個群組，按 Save。

   小工具不用到 App Store Connect 另外建 app，它跟著蒜日子一起上傳。這三步自動簽章也許會自己做，但沒有實跑過，先手動建比較保險。
2. 到 [App Store Connect 的 App 頁](https://appstoreconnect.apple.com/apps) 按「+」→ 新增 App。平台 iOS，名稱「蒜日子」（被別人用掉就換一個，這只是商店上的名字），主要語言繁體中文，套件識別碼選剛剛建的那個，SKU 隨便填，例如 `countingdays`。

Bundle ID 想用別的也可以，但要告訴 Claude 一起改 `project.yml`，兩邊不一樣會上傳失敗。

## 二、產生 API 金鑰

1. 到 App Store Connect 的 [使用者與存取權限 → 整合 → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)。
2. 在「團隊金鑰」按「+」，名稱填 `GitHub Actions`，存取權限選「管理」（Admin）。自動簽章要替你建立憑證，權限不夠會失敗。
3. 建好之後記下三樣東西：
   - Issuer ID：頁面上方那一串
   - 金鑰 ID：表格裡那一欄，10 個字元左右
   - 下載 `.p8` 檔。這個檔只能下載一次，請收好
4. 到 [Apple Developer 的 Membership](https://developer.apple.com/account#MembershipDetailsCard) 找 Team ID（10 個字元）。

## 三、把四個值貼進 GitHub

到 [repo 的 Secrets 設定頁](https://github.com/domyweb666/Counting-days/settings/secrets/actions)，按「New repository secret」，一個一個建：

| Name | 內容 |
|---|---|
| `ASC_KEY_ID` | 金鑰 ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | 用記事本打開 `.p8` 檔，整份貼上，包含 `-----BEGIN PRIVATE KEY-----` 和 `-----END PRIVATE KEY-----` 兩行 |
| `APPLE_TEAM_ID` | Team ID |

貼進去之後 GitHub 不會再顯示內容，連你自己也看不到，只能覆蓋。金鑰請不要貼到對話裡，也不要放進 repo 的任何檔案。

## 四、上傳

1. 到 [Actions 頁的 testflight 流程](https://github.com/domyweb666/Counting-days/actions/workflows/testflight.yml)。
2. 按右邊的「Run workflow」→ 綠色的「Run workflow」。
3. 等它跑完，大約 10 分鐘。綠勾表示已經傳到 Apple。

## 五、裝到手機

1. 上傳後 Apple 還要處理一下，通常 5 到 30 分鐘，好了會寄信。
2. 到 App Store Connect 的 app 頁 → TestFlight。第一次會問出口合規，蒜日子已經在設定裡聲明沒有用加密，通常不會再問；有問就選「無」。
3. 在「內部測試」建一個群組，把你自己的 Apple ID 加進去。
4. iPhone 從 App Store 裝「TestFlight」，用同一個 Apple ID 登入，就會看到蒜日子，按安裝。

之後每次程式有更新，重做第四步，TestFlight 會自己跳出新版本。每個測試版可以用 90 天。

## 版本號

每按一次上傳，建置編號自動加一（用 GitHub 的流程執行次數）。對外的版本號 `1.0.0` 寫在 `project.yml` 的 `MARKETING_VERSION`，要改的時候告訴 Claude。
