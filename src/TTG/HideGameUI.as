
namespace HideGameUI {
    bool opt_EnableRecords = false;

    string[] HidePages =
        { "UIModule_Race_Chrono"
        , "UIModule_Race_RespawnHelper"
        // , "UIModule_Race_Checkpoint"
        , "UIModule_Race_Record"
        };
    void OnMapLoad() {
        auto app = cast<CGameManiaPlanet>(GetApp());
        while (app.Network.ClientManiaAppPlayground is null) yield();
        // wait for UI layers and a few frames extra
        auto uiConf = app.Network.ClientManiaAppPlayground;
        while (uiConf.UILayers.Length < 10) yield();
        for (uint i = 0; i < uiConf.UILayers.Length; i++) {
            auto layer = uiConf.UILayers[i];
            if (layer.ManialinkPage.Length < 10) continue;
            string first100Chars = string(layer.ManialinkPage.SubStr(0, 100));
            if (first100Chars.Length < 100) continue;
            auto parts = first100Chars.Trim().Split('manialink name="');
            if (parts.Length < 2) continue;
            auto pageName = parts[1].Split('"')[0];
            if (pageName.StartsWith("UIModule_Race") && HidePages.Find(pageName) >= 0) {
                layer.IsVisible = false;
                if (pageName == "UIModule_Race_Record")
                    layer.IsVisible = opt_EnableRecords;
            }
        }
    }

    void ShowPage(const string &in showPageName) {
        auto app = cast<CGameManiaPlanet>(GetApp());
        while (app.Network.ClientManiaAppPlayground is null) return;
        // wait for UI layers and a few frames extra
        auto uiConf = app.Network.ClientManiaAppPlayground;
        while (uiConf.UILayers.Length < 10) return;
        for (uint i = 0; i < uiConf.UILayers.Length; i++) {
            auto layer = uiConf.UILayers[i];
            if (layer.ManialinkPage.Length < 10) continue;
            string first100Chars = string(layer.ManialinkPage.SubStr(0, 100));
            if (first100Chars.Length < 100) continue;
            auto parts = first100Chars.Trim().Split('manialink name="');
            if (parts.Length < 2) continue;
            auto pageName = parts[1].Split('"')[0];
            if (pageName == showPageName) {
                layer.IsVisible = true;
            }
        }
    }
}
