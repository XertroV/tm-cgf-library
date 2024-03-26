// namespace MM {
//     CGameUILayer@ _layer = null;
//     // CGameUILayer@ menuBackground = null;q
//     bool lastWasEmpty = false;

//     CGameUILayer@ getControlLayer() {
//         if (_layer is null) {
//             auto mm = cast<CTrackMania>(GetApp()).MenuManager;
//             @_layer = mm.MenuCustom_CurrentManiaApp.UILayerCreate();
//             _layer.AttachId = "ChangeMenuScreen";
//         }
//         return _layer;
//     }

//     // CGameUILayer@ getMenuPageNamed(const string &in name) {
//     //     try {
//     //         auto mc = cast<CGameManiaPlanet>(GetApp()).MenuManager.MenuCustom_CurrentManiaApp;
//     //         for (uint i = 0; i < mc.UILayers.Length; i++) {
//     //             auto item = mc.UILayers[i];
//     //             if (item.ManialinkPage.SubStr(0, 100).Contains('name="' + name + '"')) {
//     //                 return item;
//     //             }
//     //         }
//     //     } catch {}
//     //     return null;
//     // }

//     // CGameUILayer@ getMenuBackgroundLayer() {
//     //     if (menuBackground is null) {
//     //         @menuBackground = getMenuPageNamed('Overlay_MenuBackground');
//     //     }
//     //     return menuBackground;
//     // }

//     // void hideMenu3dScene() {
//     //     auto l = getMenuBackgroundLayer();
//     //     auto frame = l.LocalPage.GetFirstChild("HomeBackground_frame-global");
//     //     if (frame is null) return;
//     //     auto control = cast<CControlFrame>(frame.Control);
//     //     if (control is null) return;
//     //     if (control.Childs.Length < 3) return;
//     //     auto cf1 = cast<CControlFrame>(control.Childs[2]);
//     //     if (cf1 is null || cf1.Childs.Length < 4) return;
//     //     auto controlCamera = cast<CControlCamera>(cf1.Childs[3]);
//     //     if (controlCamera is null) return;
//     //     controlCamera.
//     // }

//     /**
//      * Set the menu page. Setting a nonexistant route will result in an empty screen (with only the BG showing), but otherwise works fine.
//      *
//      * Example routes:
//      * - /home
//      * - /local
//      * - /live
//      * - /solo
//      */
//     void setMenuPage(const string &in routeName) {
//         lastWasEmpty = routeName.EndsWith("empty");
//         getControlLayer().ManialinkPage = genManialinkPushRoute(routeName);
//     }

//     void setMenuPageEmpty() {
//         setMenuPage("/empty");
//     }

//     void RenderMenuMain_PageControl() {
//         if (UI::BeginMenu("Menu Pages")) {

//             if (UI::MenuItem("Home Page")) {
//                 setMenuPage("/home");
//             }
//             if (UI::MenuItem("Solo")) {
//                 setMenuPage("/solo");
//             }
//             if (UI::MenuItem("Live")) {
//                 setMenuPage("/live");
//             }
//             if (UI::MenuItem("Local")) {
//                 setMenuPage("/local");
//             }
//             if (UI::MenuItem("Empty")) {
//                 setMenuPage("/empty");
//             }
// #if DEV
//             if (UI::MenuItem("Profile")) {
//                 setMenuPage("/profile");
//             }
// #endif

//             UI::EndMenu();
//         }
//     }

//     /**
//      * Generate the ML wrapper for Router_Push event.
//      */
//     const string genManialinkPushRoute(const string &in routeName) {
//         string name = routeName.StartsWith("/") ? routeName : ("/" + routeName);
//         string mlCode = """
// <manialink name="CGF_AvoidHomePage" version="3">
// <script><!--

// main() {
//   declare Integer Nonce;
//   Nonce = """;
//   mlCode += tostring(Time::Now);
//   mlCode += ";\n";
//   mlCode += "  SendCustomEvent(\"Router_Push\", [\"" + name + "\", \"{}\", \"" + RouterPushJson + "\"]);\n";
//   mlCode += """
// }

// --></script>
// </manialink>
//         """;
//         return mlCode;
//     }

//     // this is the payload associated with most of the main menu transitions beteween pages. we include it mostly to avoid issues that might arise by not including it.
//     const string RouterPushJson = """{\"SaveHistory\":true,\"ResetPreviousPagesDisplayed\":true,\"KeepPreviousPagesDisplayed\":false,\"HidePreviousPage\":true,\"ShowParentPage\":false,\"ExcludeOverlays\":[]}""";
// }
