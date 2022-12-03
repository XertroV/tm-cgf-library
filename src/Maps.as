
const string MapThumbUrl(Json::Value@ map) {
    if (!bool(map['HasThumbnail'])) return "";
    return "https://trackmania.exchange/maps/screenshot_normal/" + int(map['TrackID']);
}

const string MapUrl(Json::Value@ map) {
    int trackId = map['TrackID'];
    return "https://cgf.s3.nl-1.wasabisys.com/" + trackId + ".Map.Gbx";
}

void LoadMapNow(const string &in url) {
    auto app = cast<CGameManiaPlanet>(GetApp());
    app.BackToMainMenu();
    while (!app.ManiaTitleControlScriptAPI.IsReady) yield();
    app.ManiaTitleControlScriptAPI.PlayMap(url, "", "");
}

void ReturnToMenu() {
    auto app = cast<CGameManiaPlanet>(GetApp());
    app.BackToMainMenu();
}
