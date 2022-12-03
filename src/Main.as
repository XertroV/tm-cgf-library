// Game::Client@ c1 = null;



void Main() {
    // startnew(Loop);
    // startnew(Debug::Main);
    sleep(100);
    if (S_TimerPosition.x == 0) {
        S_TimerPosition.x = Draw::GetWidth() / 2.;
    }
}

void Loop() {
    // auto x = Game::Client();
    // sleep(1000);
    // x.SendChat("test chat: " + Time::Now);
    // sleep(5000);
}

// namespace CGF {
//     Game::Client@ mainClient = null;

//     Game::Client@ GetMainClient() {
//         while (mainClient is null) {
//             yield();
//             @mainClient = Game::Client();
//         }
//     }
// }



void OnDestroyed() { _Unload(); }
void OnDisabled() { _Unload(); }
void _Unload() {
    // if (c1 !is null) c1.socket.Close();
}

void Render() {
    Debug::Render();
}

void RenderInterface() {

    // does nothing without sig_developer
    Debug::RenderInterface();
}

void RenderMenu() {
    Debug::RenderMenu();
}

// /** Render function called every frame intended only for menu items in the main menu of the `UI`.
// */
// void RenderMenuMain() {
// }

UI::InputBlocking OnKeyPress(bool down, VirtualKey key) {
    return UI::InputBlocking::DoNothing;
}

/** Called when a setting in the settings panel was changed. */
void OnSettingsChanged() {
}

/*
    Utility functions
*/

//
void NotifyDepError(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Dependency Error", msg, vec4(.9, .3, .1, .3), 15000);
}

void NotifyError(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Error", msg, vec4(.9, .3, .1, .3), 15000);
}

void NotifyWarning(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Error", msg, vec4(.9, .6, .2, .3), 15000);
}

void NotifyInfo(const string &in msg) {
    print("[INFO] " + msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg, vec4(.1, .5, .9, .3), 10000);
}

void AddSimpleTooltip(const string &in msg) {
    if (UI::IsItemHovered()) {
        UI::BeginTooltip();
        UI::Text(msg);
        UI::EndTooltip();
    }
}

const string MsToSeconds(int t) {
    return Text::Format("%.3f", float(t) / 1000.0);
}
