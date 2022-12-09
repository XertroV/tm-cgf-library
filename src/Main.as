// Game::Client@ c1 = null;



void Main() {
    // startnew(Loop);
    // startnew(Debug::Main);
    sleep(100);
    OnSettingsChanged();
}


void OnDestroyed() { _Unload(); }
void OnDisabled() { _Unload(); }
void _Unload() {
    // if (c1 !is null) c1.socket.Close();
}

void Render() {
#if DEV
    // auto screenSize = vec2(Draw::GetWidth(), Draw::GetHeight());
    // RenderHeartbeatPulse(screenSize / 2., screenSize / 4.);
#endif

    TTG::Render();
    // does nothing without sig_developer
    Debug::Render();
    Debug::RenderInterface();
}

void RenderInterface() {
}

void RenderMenu() {
    Debug::RenderMenu();
    TTG::RenderMenu();
}

/** Render function called every frame intended only for menu items in the main menu of the `UI`.
*/
void RenderMenuMain() {
    if (UI::BeginMenu(Icons::Users + " CGF")) {
        MM::RenderMenuMain_PageControl();
        UI::EndMenu();
    }
}

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
    log_info("[INFO] " + msg);
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

vec2 g_LastMousePos = vec2();

/** Called whenever the mouse moves. `x` and `y` are the viewport coordinates.
*/
void OnMouseMove(int x, int y) {
    g_LastMousePos.x = x;
    g_LastMousePos.y = y;
}
