"""把 .aso/asc/metadata.json 填進 App Store Connect。

三種模式：
  check   只讀，列出每一欄現在是什麼狀態，不寫任何東西
  fill    填文字、類別、年齡分級、截圖、審核備註與影片、選建置、內購審查截圖
  submit  把內購和這一版一起送審（不可逆，要等多米在手機上驗過 TestFlight）

App Store Connect API 沒有「App 隱私權」問卷，那一頁要在網頁上填。
這個 repo 是公開的，Actions 記錄誰都看得到，所以聯絡人姓名、電話不經過這裡，也不印出來。

用法：python .aso/asc/asc.py check --build 19
環境變數：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_PATH（.p8 檔路徑）
"""

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"
ROOT = Path(__file__).resolve().parents[2]
META_PATH = ROOT / ".aso" / "asc" / "metadata.json"

# 年齡分級問卷：未填（null）的欄位照這兩張表補。蒜日子沒有這些內容，全部填「沒有」。
# 不在兩張表裡的新欄位不猜，印出來讓人決定。
RATING_LEVEL_KEYS = {
    "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated",
    "gunsOrOtherWeapons", "horrorOrFearThemes", "matureOrSuggestiveThemes",
    "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
    "sexualContentGraphicAndNudity", "sexualContentOrNudity",
    "violenceCartoonOrFantasy", "violenceRealistic",
    "violenceRealisticProlongedGraphicOrSadistic",
}
RATING_BOOL_KEYS = {
    "gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat",
    "parentalControls", "ageAssurance", "userGeneratedContent", "advertising",
    "healthOrWellnessTopics", "socialMedia", "socialMediaAgeRestricted",
    # 2026-11-16 起送更新必填，使用者 2026-11-23 決定都填沒有
    "datingAndRelationships", "sharedLocation",
}
# 這些是「覆寫／兒童分類」，留空就是不用，不要動
RATING_LEAVE_EMPTY = {"kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride", "seventeenPlus", "developerAgeRatingInfoUrl", "gracRatingClassificationNumber"}


class AscError(Exception):
    pass


class Client:
    def __init__(self, key_id, issuer_id, key_path):
        if not (key_id and issuer_id and key_path):
            raise AscError("缺少 ASC_KEY_ID、ASC_ISSUER_ID 或 ASC_KEY_PATH")
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.private_key = Path(key_path).read_text()
        self._token = None
        self._token_made = 0.0

    def _auth(self):
        # Apple 規定 token 最長 20 分鐘，提早 5 分鐘換新的
        if self._token is None or time.time() - self._token_made > 15 * 60:
            now = int(time.time())
            self._token = jwt.encode(
                {"iss": self.issuer_id, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
                self.private_key,
                algorithm="ES256",
                headers={"kid": self.key_id, "typ": "JWT"},
            )
            self._token_made = time.time()
        return {"Authorization": f"Bearer {self._token}"}

    def call(self, method, path, body=None, params=None, allow_404=False):
        url = path if path.startswith("http") else API + path
        response = requests.request(method, url, headers=self._auth(), json=body, params=params, timeout=60)
        if allow_404 and response.status_code == 404:
            return None
        if response.status_code >= 400:
            raise AscError(f"{method} {path} → {response.status_code}\n{response.text[:2000]}")
        if response.status_code == 204 or not response.content:
            return {}
        return response.json()

    def get(self, path, params=None, allow_404=False):
        return self.call("GET", path, params=params, allow_404=allow_404)

    def post(self, path, body):
        return self.call("POST", path, body=body)

    def patch(self, path, body):
        return self.call("PATCH", path, body=body)

    def delete(self, path):
        return self.call("DELETE", path)


def load_meta():
    meta = json.loads(META_PATH.read_text(encoding="utf-8"))
    limits = {"name": 30, "subtitle": 30}
    for field, limit in limits.items():
        if len(meta["appInfo"][field]) > limit:
            raise AscError(f"{field} 超過 {limit} 字：{meta['appInfo'][field]}")
    if len(meta["versionLocalization"]["keywords"]) > 100:
        raise AscError("關鍵字超過 100 字")
    if len(meta["versionLocalization"]["promotionalText"]) > 170:
        raise AscError("宣傳文字超過 170 字")
    if len(meta["versionLocalization"].get("whatsNew", "")) > 4000:
        raise AscError("新功能說明超過 4000 字")
    if len(meta["versionLocalization"]["description"]) > 4000:
        raise AscError("描述超過 4000 字")
    return meta


def say(text):
    print(text, flush=True)


# ---------- 找東西 ----------

def find_app(client, bundle_id):
    data = client.get("/v1/apps", {"filter[bundleId]": bundle_id})["data"]
    if len(data) != 1:
        raise AscError(f"找不到 bundle id 為 {bundle_id} 的 app（找到 {len(data)} 個）")
    return data[0]


def editable_app_info(client, app_id):
    infos = client.get(f"/v1/apps/{app_id}/appInfos")["data"]
    # 還沒上架過只會有一份；上架後會多一份「已發布」的，那份不能改
    # 已經上架、還沒建新版本時只有「已發布」那份，回 nil，名稱、副標、類別、年齡分級沿用上架版
    editable = [i for i in infos if i["attributes"].get("state") != "READY_FOR_DISTRIBUTION"]
    if not editable:
        if not infos:
            raise AscError("這個 app 一份 App 資訊（appInfo）都沒有，到網頁確認")
        return None
    return editable[0]


def find_version(client, app_id, version_string):
    versions = client.get(f"/v1/apps/{app_id}/appStoreVersions", {"filter[platform]": "IOS", "limit": 50})["data"]
    for v in versions:
        if v["attributes"]["versionString"] == version_string:
            return v
    # 建 app 時後台會自動開一版（通常叫 1.0），版號不同但就是要用的那一版，fill 時改成 metadata 的版號
    for v in versions:
        if v["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION":
            return v
    return None


def find_localization(client, path, locale):
    for loc in client.get(path, {"limit": 50})["data"]:
        if loc["attributes"]["locale"] == locale:
            return loc
    return None


def find_build(client, app_id, version_string, build_number):
    builds = client.get("/v1/builds", {
        "filter[app]": app_id,
        "filter[preReleaseVersion.version]": version_string,
        "filter[version]": str(build_number),
        "limit": 5,
    })["data"]
    if not builds:
        raise AscError(f"找不到 {version_string} ({build_number}) 這個建置")
    build = builds[0]
    state = build["attributes"]["processingState"]
    if state != "VALID":
        raise AscError(f"建置 {build_number} 還在處理中（{state}），等 Apple 處理完再跑一次")
    return build


def find_iap(client, app_id, product_id):
    items = client.get(f"/v1/apps/{app_id}/inAppPurchasesV2", {"filter[productId]": product_id})["data"]
    if len(items) != 1:
        raise AscError(f"找不到內購 {product_id}")
    return items[0]


# ---------- 上傳檔案 ----------

def upload_asset(client, create_path, create_type, relationship, file_path):
    file_path = ROOT / file_path
    if not file_path.is_file():
        raise AscError(f"找不到檔案 {file_path}")
    raw = file_path.read_bytes()
    created = client.post(create_path, {"data": {
        "type": create_type,
        "attributes": {"fileName": file_path.name, "fileSize": len(raw)},
        "relationships": relationship,
    }})["data"]
    for op in created["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        chunk = raw[op["offset"]:op["offset"] + op["length"]]
        response = requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=300)
        if response.status_code >= 400:
            raise AscError(f"上傳 {file_path.name} 失敗：{response.status_code} {response.text[:500]}")
    client.patch(f"{create_path}/{created['id']}", {"data": {
        "type": create_type,
        "id": created["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(raw).hexdigest()},
    }})
    return created["id"]


def wait_delivered(client, path, label):
    # Apple 收到檔案後還要自己處理，FAILED 時要大聲講，不然送審才發現圖是壞的
    for _ in range(40):
        state = client.get(path)["data"]["attributes"].get("assetDeliveryState") or {}
        status = state.get("state")
        if status == "COMPLETE":
            return
        if status == "FAILED":
            raise AscError(f"{label} Apple 處理失敗：{state.get('errors')}")
        time.sleep(3)
    raise AscError(f"{label} 等了 2 分鐘 Apple 還沒處理完，到網頁上看一下")


# ---------- check ----------

def check(client, meta, build_number):
    problems = []
    app = find_app(client, meta["bundleId"])
    app_id = app["id"]
    say(f"App：{app['attributes']['name']}（主要語言 {app['attributes'].get('primaryLocale')}）")
    if app["attributes"].get("contentRightsDeclaration") != meta["contentRights"]:
        problems.append("內容版權聲明還沒填")

    info = editable_app_info(client, app_id)
    if info is None:
        say("App 資訊：沿用已上架的（名稱、副標、類別、年齡分級）")
    else:
        check_app_info(client, meta, info, problems)

    check_version(client, meta, app_id, build_number, problems)


def check_app_info(client, meta, info, problems):
    loc = find_localization(client, f"/v1/appInfos/{info['id']}/appInfoLocalizations", meta["locale"])
    if loc is None:
        problems.append(f"App 資訊沒有 {meta['locale']} 語言")
    else:
        for key, want in meta["appInfo"].items():
            have = loc["attributes"].get(key)
            say(f"  {key}：{'一致' if have == want else '要更新'}")
            if have != want:
                problems.append(f"App 資訊的 {key}")

    cats = client.get(f"/v1/appInfos/{info['id']}", {"include": "primaryCategory,secondaryCategory"})["data"]["relationships"]
    primary = (cats["primaryCategory"].get("data") or {}).get("id")
    secondary = (cats["secondaryCategory"].get("data") or {}).get("id")
    say(f"  類別：{primary} / {secondary}")
    if (primary, secondary) != (meta["primaryCategory"], meta["secondaryCategory"]):
        problems.append("類別")

    rating = client.get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]["attributes"]
    empty = [k for k, v in rating.items() if v is None and k not in RATING_LEAVE_EMPTY]
    say(f"  年齡分級未填：{empty or '無'}")
    if empty:
        problems.append("年齡分級")


def check_version(client, meta, app_id, build_number, problems):
    version = find_version(client, app_id, meta["version"])
    if version is None:
        problems.append(f"還沒有 {meta['version']} 這一版")
    else:
        attrs = version["attributes"]
        say(f"版本 {attrs['versionString']}：{attrs.get('appStoreState')}，發布方式 {attrs.get('releaseType')}，著作權 {'有' if attrs.get('copyright') else '沒有'}")
        vloc = find_localization(client, f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations", meta["locale"])
        if vloc is None:
            problems.append(f"版本沒有 {meta['locale']} 語言")
        else:
            for key, want in meta["versionLocalization"].items():
                have = vloc["attributes"].get(key)
                if have != want:
                    problems.append(f"版本的 {key}")
                say(f"  {key}：{'一致' if have == want else '要更新'}")
            sets = client.get(f"/v1/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets", {"include": "appScreenshots"})
            for s in sets["data"]:
                count = len(s["relationships"]["appScreenshots"].get("data") or [])
                say(f"  截圖 {s['attributes']['screenshotDisplayType']}：{count} 張")
        has_build = client.get(f"/v1/appStoreVersions/{version['id']}/relationships/build").get("data")
        say(f"  選了建置：{'有' if has_build else '沒有'}")
        detail = client.get(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail", allow_404=True)
        if detail is None or detail.get("data") is None:
            problems.append("審核資訊整頁沒填")
        else:
            d = detail["data"]["attributes"]
            for key in ("contactFirstName", "contactLastName", "contactPhone"):
                # 只說有沒有，不印內容（公開 repo 的記錄）
                say(f"  審核聯絡人 {key}：{'有' if d.get(key) else '沒有'}")
                if not d.get(key):
                    problems.append(f"審核聯絡人 {key}（要在網頁上填）")

    try:
        build = find_build(client, app_id, meta["version"], build_number)
        say(f"建置 {build_number}：可用")
    except AscError as error:
        problems.append(str(error))

    schedule = client.get(f"/v1/apps/{app_id}/appPriceSchedule", allow_404=True)
    say(f"App 售價：{'已設定' if schedule and schedule.get('data') else '沒設定'}")
    if not (schedule and schedule.get("data")):
        problems.append("App 售價（免費）沒設定")
    availability = client.get(f"/v1/apps/{app_id}/appAvailabilityV2", allow_404=True)
    say(f"銷售地區：{'已設定' if availability and availability.get('data') else '沒設定'}")
    if not (availability and availability.get("data")):
        problems.append("銷售地區沒設定")

    iap = find_iap(client, app_id, meta["inAppPurchase"]["productId"])
    say(f"內購 {iap['attributes']['productId']}：{iap['attributes']['state']}")
    shot = client.get(f"/v2/inAppPurchases/{iap['id']}/appStoreReviewScreenshot", allow_404=True)
    say(f"  內購審查截圖：{'有' if shot and shot.get('data') else '沒有'}")

    say("")
    say("App 隱私權問卷 API 讀不到，要在網頁上看。")
    if problems:
        say("還沒好的：")
        for p in problems:
            say(f"  - {p}")
    else:
        say("API 看得到的欄位都好了。")


# ---------- fill ----------

def fill(client, meta, build_number):
    app = find_app(client, meta["bundleId"])
    app_id = app["id"]

    if app["attributes"].get("contentRightsDeclaration") != meta["contentRights"]:
        client.patch(f"/v1/apps/{app_id}", {"data": {"type": "apps", "id": app_id, "attributes": {"contentRightsDeclaration": meta["contentRights"]}}})
        say("內容版權聲明：已填")

    info = editable_app_info(client, app_id)
    if info is None:
        say("App 資訊：沿用已上架的（名稱、副標、類別、年齡分級）")
    else:
        fill_app_info(client, meta, info)

    fill_availability(client, app_id, meta["availability"])

    version = find_version(client, app_id, meta["version"])
    version_attrs = {"copyright": meta["copyright"], "releaseType": meta["releaseType"]}
    if version is None:
        version = client.post("/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": meta["version"], **version_attrs},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }})["data"]
        say(f"版本 {meta['version']}：新建")
    else:
        version_attrs["versionString"] = meta["version"]
        client.patch(f"/v1/appStoreVersions/{version['id']}", {"data": {"type": "appStoreVersions", "id": version["id"], "attributes": version_attrs}})
        say(f"版本 {meta['version']}：著作權、審核過自動發布 已填")

    vloc_path = f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations"
    vloc = find_localization(client, vloc_path, meta["locale"])
    if vloc is None:
        vloc = client.post("/v1/appStoreVersionLocalizations", {"data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": meta["locale"], **meta["versionLocalization"]},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}},
        }})["data"]
    else:
        client.patch(f"/v1/appStoreVersionLocalizations/{vloc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": vloc["id"], "attributes": meta["versionLocalization"]}})
    say("描述、關鍵字、宣傳文字、支援與行銷網址：已填")

    fill_screenshots(client, vloc["id"], meta["screenshots"])

    build = find_build(client, app_id, meta["version"], build_number)
    client.patch(f"/v1/appStoreVersions/{version['id']}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
    say(f"建置：選了 {build_number}")

    fill_review(client, version["id"], meta["review"])
    fill_iap_screenshot(client, app_id, meta["inAppPurchase"])

    say("")
    say("API 能填的都填了。還要在網頁上做：App 隱私權（不收集資料）、審核聯絡人姓名電話（如果 check 說沒有）。")



def fill_app_info(client, meta, info):
    loc = find_localization(client, f"/v1/appInfos/{info['id']}/appInfoLocalizations", meta["locale"])
    if loc is None:
        raise AscError(f"App 資訊沒有 {meta['locale']} 語言。主要語言要在建立 app 時選，請到網頁確認")
    client.patch(f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": meta["appInfo"]}})
    say("名稱、副標、隱私權政策網址：已填")

    client.patch(f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": meta["primaryCategory"]}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": meta["secondaryCategory"]}},
    }}})
    say("類別：已填")

    rating = client.get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    updates, unknown = {}, []
    for key, value in rating["attributes"].items():
        if value is not None or key in RATING_LEAVE_EMPTY:
            continue
        if key in RATING_LEVEL_KEYS:
            updates[key] = "NONE"
        elif key in RATING_BOOL_KEYS:
            updates[key] = False
        else:
            unknown.append(key)
    if updates:
        client.patch(f"/v1/ageRatingDeclarations/{rating['id']}", {"data": {"type": "ageRatingDeclarations", "id": rating["id"], "attributes": updates}})
    say(f"年齡分級：補了 {len(updates)} 欄")
    if unknown:
        raise AscError(f"年齡分級有不認得的新欄位，沒有亂填：{unknown}")


def fill_availability(client, app_id, spec):
    existing = client.get(f"/v1/apps/{app_id}/appAvailabilityV2", allow_404=True)
    if existing and existing.get("data"):
        say("銷售地區：本來就設定過，不動")
        return
    territories = client.get("/v1/territories", {"limit": 200})["data"]
    if len(territories) < 100:
        raise AscError(f"地區清單只拿到 {len(territories)} 個，不像完整清單，停下來")
    excluded = set(spec["excludeTerritories"])
    refs, included = [], []
    for territory in territories:
        local_id = "${" + territory["id"] + "}"
        refs.append({"type": "territoryAvailabilities", "id": local_id})
        included.append({
            "type": "territoryAvailabilities",
            "id": local_id,
            "attributes": {"available": territory["id"] not in excluded},
            "relationships": {"territory": {"data": {"type": "territories", "id": territory["id"]}}},
        })
    client.call("POST", "/v2/appAvailabilities", body={
        "data": {
            "type": "appAvailabilities",
            "attributes": {"availableInNewTerritories": spec["availableInNewTerritories"]},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
                "territoryAvailabilities": {"data": refs},
            },
        },
        "included": included,
    })
    say(f"銷售地區：{len(territories) - len(excluded)} 個，不含 {sorted(excluded)}")


def fill_screenshots(client, vloc_id, spec):
    folder = ROOT / spec["folder"]
    files = sorted(p for p in folder.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
    if not 1 <= len(files) <= 10:
        raise AscError(f"{folder} 要有 1 到 10 張截圖，現在 {len(files)} 張")
    sets = client.get(f"/v1/appStoreVersionLocalizations/{vloc_id}/appScreenshotSets")["data"]
    target = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == spec["displayType"]), None)
    if target is None:
        target = client.post("/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": spec["displayType"]},
            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": vloc_id}}},
        }})["data"]
    # 重跑時先清掉舊的，順序才會跟資料夾一樣，也不會疊成 20 張
    for old in client.get(f"/v1/appScreenshotSets/{target['id']}/appScreenshots")["data"]:
        client.delete(f"/v1/appScreenshots/{old['id']}")
    relationship = {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": target["id"]}}}
    for file in files:
        shot_id = upload_asset(client, "/v1/appScreenshots", "appScreenshots", relationship, file.relative_to(ROOT))
        wait_delivered(client, f"/v1/appScreenshots/{shot_id}", file.name)
        say(f"  截圖 {file.name}：好了")
    say(f"截圖：{len(files)} 張")


def fill_review(client, version_id, spec):
    # 聯絡人姓名、電話、信箱在網頁上填（公開 repo 不放個資），這裡不碰
    attrs = {"demoAccountRequired": spec["demoAccountRequired"], "notes": spec["notes"]}
    existing = client.get(f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail", allow_404=True)
    if existing is None or existing.get("data") is None:
        detail = client.post("/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails",
            "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
        }})["data"]
    else:
        detail = existing["data"]
        client.patch(f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": attrs}})
    say("審核備註、信箱、不需登入：已填")

    attachments = client.get(f"/v1/appStoreReviewDetails/{detail['id']}/appStoreReviewAttachments")["data"]
    name = Path(spec["attachment"]).name
    for old in attachments:
        if old["attributes"].get("fileName") == name:
            client.delete(f"/v1/appStoreReviewAttachments/{old['id']}")
    relationship = {"appStoreReviewDetail": {"data": {"type": "appStoreReviewDetails", "id": detail["id"]}}}
    attachment_id = upload_asset(client, "/v1/appStoreReviewAttachments", "appStoreReviewAttachments", relationship, spec["attachment"])
    wait_delivered(client, f"/v1/appStoreReviewAttachments/{attachment_id}", name)
    say("審核影片：好了")


def fill_iap_screenshot(client, app_id, spec):
    iap = find_iap(client, app_id, spec["productId"])
    existing = client.get(f"/v2/inAppPurchases/{iap['id']}/appStoreReviewScreenshot", allow_404=True)
    if existing and existing.get("data"):
        say(f"內購審查截圖：本來就有，不動（內購狀態 {iap['attributes']['state']}）")
        return
    relationship = {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap["id"]}}}
    shot_id = upload_asset(client, "/v1/inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseAppStoreReviewScreenshots", relationship, spec["reviewScreenshot"])
    wait_delivered(client, f"/v1/inAppPurchaseAppStoreReviewScreenshots/{shot_id}", "內購審查截圖")
    say("內購審查截圖：好了")


# ---------- submit ----------

def submit(client, meta, build_number):
    app = find_app(client, meta["bundleId"])
    app_id = app["id"]
    version = find_version(client, app_id, meta["version"])
    if version is None:
        raise AscError("還沒有這一版，先跑 fill")
    chosen = client.get(f"/v1/appStoreVersions/{version['id']}/relationships/build").get("data")
    build = find_build(client, app_id, meta["version"], build_number)
    if not chosen or chosen["id"] != build["id"]:
        raise AscError(f"這一版選的建置不是 {build_number}，先跑 fill")

    # 第一個內購要跟 app 一起審；沒一起送，審查員按購買會失敗而退件，所以內購送不出去就整個停
    iap = find_iap(client, app_id, meta["inAppPurchase"]["productId"])
    state = iap["attributes"]["state"]
    if state == "READY_TO_SUBMIT":
        client.post("/v1/inAppPurchaseSubmissions", {"data": {
            "type": "inAppPurchaseSubmissions",
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap["id"]}}},
        }})
        say("內購：已加入送審")
    elif state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"):
        say(f"內購：{state}，不用再送")
    else:
        raise AscError(f"內購狀態是 {state}，還不能送審。到網頁上看內購頁缺什麼")

    submission = client.post("/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions",
        "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
    }})["data"]
    client.post("/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}},
        },
    }})
    client.patch(f"/v1/reviewSubmissions/{submission['id']}", {"data": {"type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
    say(f"已送審：{meta['version']} ({build_number})，審核通過後自動上架")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["check", "fill", "submit"])
    parser.add_argument("--build", type=int, required=True)
    args = parser.parse_args()
    if args.build <= 0:
        raise AscError("建置號要是正整數")

    client = Client(os.environ.get("ASC_KEY_ID"), os.environ.get("ASC_ISSUER_ID"), os.environ.get("ASC_KEY_PATH"))
    meta = load_meta()
    {"check": check, "fill": fill, "submit": submit}[args.mode](client, meta, args.build)


if __name__ == "__main__":
    try:
        main()
    except AscError as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
