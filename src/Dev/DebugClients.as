namespace Debug {
#if SIG_DEVELOPER
[Setting category="Debug" name="Show Clients Debug Window"]
bool S_ShowClientsDebugWindow = true;

void RenderInterface() {
    if (!S_ShowClientsDebugWindow) return;
    UI::SetNextWindowSize(800, 450);
    if (UI::Begin(Meta::ExecutingPlugin().Name + ": Debug", S_ShowClientsDebugWindow)) {
        UI::BeginTabBar("debug tab bar", UI::TabBarFlags::NoCloseWithMiddleMouseButton | UI::TabBarFlags::NoTooltip);
        for (uint i = 0; i < Tabs.Length; i++) {
            Tabs[i].DrawTab();
        }
        UI::EndTabBar();
    }
    UI::End();
}

void RenderMenu() {
    if (UI::MenuItem(Icons::ExclamationTriangle + " Client Debug | " + Meta::ExecutingPlugin().Name, "", S_ShowClientsDebugWindow)) {
        S_ShowClientsDebugWindow = !S_ShowClientsDebugWindow;
    }
}


Game::Client@[] allClients;
Game::Client@ selectedClient;


class ClientsTab : Tab {
    ClientsTab() {
        super("Clients");
    }

    uint newClientDisabledTill = 0;

    void DrawInner() override {
        UI::AlignTextToFramePadding();
        UI::Text("Debug Clients: " + allClients.Length);
        UI::SameLine();
        UI::BeginDisabled(newClientDisabledTill > Time::Now);
        if (UI::Button("New Client")) {
            newClientDisabledTill = Time::Now + 750;
            startnew(CoroutineFunc(CreateAndAddNewClient));
        }
        UI::EndDisabled();
        UI::Separator();
        if (allClients.Length < 0) {
            UI::Text("No Clients.");
        } else {
            for (uint i = 0; i < allClients.Length; i++) {
                allClients[i].DrawDebug();
            }
        }
    }

    void CreateAndAddNewClient() {
        allClients.InsertLast(Game::Client("DebugClient-" + Time::Now));
    }
}



class ChatTab : Tab {
    ChatTab() {
        super("Chat");
    }

    string m_chatMsg;

    void SendChatMsg() {
        selectedClient.SendChat(m_chatMsg, CGF::Visibility::global);
        m_chatMsg = "";
    }

    void DrawInner() override {
        if (selectedClient is null) {
            if (allClients.Length == 0) return;
            @selectedClient = allClients[0];
        }
        if (UI::BeginCombo("Selected Client", selectedClient.name)) {
            for (uint i = 0; i < allClients.Length; i++) {
                auto item = allClients[i];
                if (UI::Selectable(item.name, @item == @selectedClient)) {
                    @selectedClient = item;
                }
            }
            UI::EndCombo();
        }
        UI::AlignTextToFramePadding();
        UI::Text("Msg: ");
        UI::SameLine();
        bool changed;
        m_chatMsg = UI::InputText("##chat-msg", m_chatMsg, changed, UI::InputTextFlags::EnterReturnsTrue);
        if (changed) UI::SetKeyboardFocusHere(-1);
        UI::SameLine();
        if (UI::Button("Send") || changed) {
            startnew(CoroutineFunc(SendChatMsg));
        }
        UI::Separator();
        if (UI::BeginChild("##debug-chat", vec2(), true, UI::WindowFlags::AlwaysAutoResize)) {
            UI::Text("Chat Ix: " + selectedClient.globalChatNextIx);
            auto @chat = selectedClient.globalChat;
            for (int i = 0; i < selectedClient.globalChat.Length; i++) {
                auto thisIx = (int(selectedClient.globalChatNextIx) - i - 1 + chat.Length) % chat.Length;
                UI::Text("thisIx: " + thisIx);
                auto msg = chat[thisIx];
                if (msg is null) continue;
                UI::SameLine();
                UI::TextWrapped(Time::FormatString("%H:%M", int64(msg['ts'])) + " [ " + string(msg['from']['username']) + " ]: " + string(msg['payload']['content']));
            }
        }
        UI::EndChild();
    }
}












auto clientsTab = ClientsTab();
auto chatTab = ChatTab();

Tab@[] Tabs = {clientsTab, chatTab};



#else
void RenderInterface() {}
void RenderMenu() {}
#endif
}
