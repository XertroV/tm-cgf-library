
// void TestFunc() {
//     auto mm = cast<CTrackMania>(GetApp()).MenuManager;
//     // auto scriptHandler = mm.ManialinkScriptHandlerMenus;
//     auto layer = mm.MenuCustom_CurrentManiaApp.UILayerCreate();
//     yield();
//     layer.AttachId = "ChangeMenuScreen";
//     layer.ManialinkPage = """
// <manialink name="CGF_AvoidHomePage" version="3">
// <script><!--

// main() {
//   yield;
//   SendCustomEvent("Router_Push", ["/local", "{}", "{}"]);
// }

// --></script>
// </manialink>
//     """;
// }

namespace MM {
    CGameUILayer@ _layer = null;

    CGameUILayer@ getControlLayer() {
        if (_layer is null) {
            auto mm = cast<CTrackMania>(GetApp()).MenuManager;
            @_layer = mm.MenuCustom_CurrentManiaApp.UILayerCreate();
            _layer.AttachId = "ChangeMenuScreen";
        }
        return _layer;
    }

    /**
     * Set the menu page. Setting a nonexistant route will result in an empty screen (with only the BG showing), but otherwise works fine.
     *
     * Example routes:
     * - /home
     * - /local
     * - /live
     * - /solo
     */
    void setMenuPage(const string &in routeName) {
        getControlLayer().ManialinkPage = genManialinkPushRoute(routeName);
    }

    void RenderMenuMain_PageControl() {
        if (UI::BeginMenu("Menu Pages")) {

            if (UI::MenuItem("Home Page")) {
                setMenuPage("/home");
            }
            if (UI::MenuItem("Solo")) {
                setMenuPage("/solo");
            }
            if (UI::MenuItem("Live")) {
                setMenuPage("/live");
            }
            if (UI::MenuItem("Local")) {
                setMenuPage("/local");
            }
            if (UI::MenuItem("Empty")) {
                setMenuPage("/empty");
            }

            UI::EndMenu();
        }
    }

    /**
     * Generate the ML wrapper for Router_Push event.
     */
    const string genManialinkPushRoute(const string &in routeName) {
        string name = routeName.StartsWith("/") ? routeName : ("/" + routeName);
        string mlCode = """
<manialink name="CGF_AvoidHomePage" version="3">
<script><!--

main() {
  yield;
  declare Integer Nonce;
  Nonce = """;
  mlCode += tostring(Time::Now);
  mlCode += ";\n";
  mlCode += "  SendCustomEvent(\"Router_Push\", [\"" + name + "\", \"{}\", \"" + RouterPushJson + "\"]);\n";
  mlCode += """
}

--></script>
</manialink>
        """;
        return mlCode;
    }

    // this is the payload associated with most of the main menu transitions beteween pages. we include it mostly to avoid issues that might arise by not including it.
    const string RouterPushJson = """{\"SaveHistory\":true,\"ResetPreviousPagesDisplayed\":true,\"KeepPreviousPagesDisplayed\":false,\"HidePreviousPage\":true,\"ShowParentPage\":false,\"ExcludeOverlays\":[]}""";
}
