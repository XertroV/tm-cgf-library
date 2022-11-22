namespace Debug {
#if SIG_DEVELOPER
[Setting category="Debug" name="Show Clients Debug Window"]
bool S_ShowClientsDebugWindow = true;


Game::Client@[] allClients;
DebugClientWindow@[] allWindows;


void Main() {
    clientsTab.CreateAndAddNewClient();
}


void RenderInterface() {
    for (uint i = 0; i < allWindows.Length; i++) {
        allWindows[i].RenderInterface();
    }
    if (!S_ShowClientsDebugWindow) return;
    UI::SetNextWindowSize(800, 450);
    if (UI::Begin(Meta::ExecutingPlugin().Name + ": Debug", S_ShowClientsDebugWindow)) {
        // DrawClientSelection();
        clientsTab.DrawInner();
    }
    UI::End();
}

void RenderMenu() {
    if (UI::MenuItem(Icons::ExclamationTriangle + " Client Debug | " + Meta::ExecutingPlugin().Name, "", S_ShowClientsDebugWindow)) {
        S_ShowClientsDebugWindow = !S_ShowClientsDebugWindow;
    }
}


// void DrawClientSelection() {
//     if (selectedClient is null) {
//         if (allClients.Length == 0) return;
//         @selectedClient = allClients[0];
//     }
//     if (UI::BeginCombo("Selected Client", selectedClient.name)) {
//         for (uint i = 0; i < allClients.Length; i++) {
//             auto item = allClients[i];
//             if (UI::Selectable(item.name, @item == @selectedClient)) {
//                 @selectedClient = item;
//             }
//         }
//         UI::EndCombo();
//     }
// }


class DebugClientWindow {
    Game::Client@ client;

    bool windowVisible = true;

    LobbiesTab@ lobbiesTab;
    ChatTab@ chatTab;
    RoomsTab@ roomsTab;
    Tab@[] tabs;

    DebugClientWindow(Game::Client@ client) {
        @this.client = client;
        @lobbiesTab = LobbiesTab(this);
        @chatTab = ChatTab(this);
        @roomsTab = RoomsTab(this);
        tabs.InsertLast(chatTab);
        tabs.InsertLast(lobbiesTab);
        tabs.InsertLast(roomsTab);
        windowVisible = true;
        client.AddMessageHandler("LOBBY_LIST", CGF::MessageHandler(lobbiesTab.OnLobbyList));
    }

    void RenderInterface() {
        if (!windowVisible) return;
        UI::SetNextWindowSize(850, 600);
        if (UI::Begin(Meta::ExecutingPlugin().Name + " Client Debug: " + client.name, windowVisible)) {
            UI::Text("State: " + tostring(client.state));
            UI::Text("Connected For: " + Time::Format(uint32(client.ConnectionDuration), false, true, false));
            UI::Text("Curr Scope: " + tostring(client.currScope));
            if (client.lobbyInfo !is null) UI::Text("Curr Lobby Info: " + client.lobbyInfo.PrettyString());
            if (client.roomInfo !is null) UI::Text("Curr Room Info: " + client.roomInfo.ToString());
            UI::BeginTabBar("tb##"+client.name, UI::TabBarFlags::NoCloseWithMiddleMouseButton | UI::TabBarFlags::NoTooltip);
            for (uint i = 0; i < tabs.Length; i++) {
                tabs[i].DrawTab();
            }
            UI::EndTabBar();
        }
        UI::End();
    }
}


class ClientsTab : Tab {
    ClientsTab() {
        super("Clients");
    }

    uint newClientDisabledTillCount = 0;

    void DrawInner() override {
        UI::AlignTextToFramePadding();
        UI::Text("Debug Clients: " + allClients.Length);
        UI::SameLine();
        UI::BeginDisabled(allClients.Length < newClientDisabledTillCount);
        if (UI::Button("New Client")) {
            newClientDisabledTillCount = allClients.Length + 1;
            startnew(CoroutineFunc(CreateAndAddNewClient));
        }
        UI::EndDisabled();
        UI::Separator();
        if (allWindows.Length < 0) {
            UI::Text("No Clients.");
        } else {
            for (uint i = 0; i < allWindows.Length; i++) {
                auto window = allWindows[i];
                window.client.DrawDebug();
                if (UI::Button((window.windowVisible ? "Hide" : "Show") + "##" + window.client.name)) {
                    window.windowVisible = !window.windowVisible;
                }
            }
        }
    }

    void CreateAndAddNewClient() {
        auto client = Game::Client("DebugClient-" + allClients.Length);
        auto window = DebugClientWindow(client);
        allClients.InsertLast(client);
        allWindows.InsertLast(window);
    }
}



class ChatTab : Tab {
    DebugClientWindow@ parent;

    ChatTab(DebugClientWindow@ parent) {
        @this.parent = parent;
        super("Chat");
    }

    string m_chatMsg;

    void SendChatMsg() {
        parent.client.SendChat(m_chatMsg, CGF::Visibility::global);
        m_chatMsg = "";
    }

    void DrawInner() override {
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
        if (parent.client is null) return;
        UI::Separator();
        if (UI::BeginChild("##debug-chat", vec2(), true, UI::WindowFlags::AlwaysAutoResize)) {
            UI::Text("Chat Ix: " + parent.client.chatNextIx);
            auto @chat = parent.client.mainChat;
            for (int i = 0; i < parent.client.mainChat.Length; i++) {
                auto thisIx = (int(parent.client.chatNextIx) - i - 1 + chat.Length) % chat.Length;
                auto msg = chat[thisIx];
                if (msg is null) break;
                UI::Text("" + thisIx + ".");
                UI::SameLine();
                UI::TextWrapped(Time::FormatString("%H:%M", int64(msg['ts'])) + " [ " + string(msg['from']['username']) + " ]: " + string(msg['payload']['content']));
            }
        }
        UI::EndChild();
    }
}



class LobbiesTab : Tab {
    DebugClientWindow@ parent;

    LobbiesTab(DebugClientWindow@ parent) {
        @this.parent = parent;
        super("Lobbies");
    }

    uint nbLobbies;
    Json::Value@[] lobbies;

    bool OnLobbyList(Json::Value@ j) {
        auto pl = j['payload'];
        if (pl.GetType() == Json::Type::Array) {
            nbLobbies = pl.Length;
            lobbies.Resize(nbLobbies);
            for (uint i = 0; i < pl.Length; i++) {
                @lobbies[i] = pl[i];
            }
        }
        return true;
    }

    string m_LobbyName;

    void DrawInner() override {
        UI::AlignTextToFramePadding();
        UI::Text("There are " + nbLobbies + " Lobbies");
        if (allClients.Length == 0) {
            UI::Text("\\$f40Create a client, first.");
            return;
        }
        UI::SameLine();
        if (UI::Button("Refresh")) {
            parent.client.SendPayload("LIST_LOBBIES", "", CGF::Visibility::none);
            auto @oldHandlers = parent.client.GetMessageHandlers("LOBBY_LIST");
            oldHandlers.Resize(0);
            parent.client.AddMessageHandler("LOBBY_LIST", CGF::MessageHandler(OnLobbyList));
        }
        UI::Separator();
        if (UI::CollapsingHeader("Create New Lobby")) {
            UI::AlignTextToFramePadding();
            UI::Text("Name: ");
            UI::SameLine();
            bool changed;
            m_LobbyName = UI::InputText("##lobby-name", m_LobbyName, changed, UI::InputTextFlags::EnterReturnsTrue);
            if (changed) UI::SetKeyboardFocusHere(-1);
            UI::SameLine();
            if (UI::Button("Create") || changed) {
                startnew(CoroutineFunc(CreateLobby));
            }
        }

        UI::Separator();
        for (uint i = 0; i < lobbies.Length; i++) {
            auto lobby = lobbies[i];
            string name = string(lobby['name']);
            if (UI::CollapsingHeader("Lobby: " + name)) {
                UI::AlignTextToFramePadding();
                UI::Text("n_clients: " + int(lobby['n_clients']));
                UI::SameLine();
                UI::Text("n_rooms: " + int(lobby['n_rooms']));
                UI::SameLine();
                if (parent.client.currScope == Game::Scope::MainLobby && UI::Button("Join##join-lobby-"+name)) {
                    parent.client.JoinLobby(name);
                }
                if (parent.client.currScope == Game::Scope::InGameLobby && UI::Button("Leave##leave-lobby-"+name)) {
                    parent.client.LeaveLobby();
                }
                UI::Separator();
                // todo: if rooms, draw
            }
        }
    }

    void CreateLobby() {
        if (m_LobbyName.Length < 3) return;
        auto pl = Json::Object();
        pl['name'] = m_LobbyName;
        m_LobbyName = "";
        parent.client.SendPayload("CREATE_LOBBY", pl, CGF::Visibility::global);
    }
}



class RoomsTab : Tab {
    DebugClientWindow@ parent;

    Json::Value@ createdRoomDetails;

    RoomsTab(DebugClientWindow@ parent) {
        @this.parent = parent;
        super("Rooms");
    }

    bool OnCreatedRoom(Json::Value@ j) {
        @createdRoomDetails = j['payload'];
        return true;
    }

    string m_roomName;
    bool m_isPublic = true;
    int m_playerLimit = 2;
    int m_nbTeams = 2;
    uint createRoomTimeout = 0;
    string m_joinCode;

    void DrawInner() override {
        if (parent.client.lobbyInfo is null) return;
        auto li = parent.client.lobbyInfo;
        int nbRooms = li.n_rooms;
        auto rooms = li.rooms;
        string idSuffix = "##" + parent.client.name + "-" + li.name;
        UI::AlignTextToFramePadding();
        UI::Text("Nb Rooms: " + nbRooms);
        UI::Separator();
        bool changed;
        if (UI::CollapsingHeader("Create Room")) {
            m_roomName = UI::InputText("Room Name" + idSuffix, m_roomName, changed);
            m_isPublic = UI::Checkbox("Is Public?" + idSuffix, m_isPublic);
            m_playerLimit = UI::SliderInt("Max Players", m_playerLimit, MIN_PLAYERS, MAX_PLAYERS);
            m_playerLimit = Math::Max(MIN_PLAYERS, Math::Min(MAX_PLAYERS, m_playerLimit));  // manual values can be inputed outside minmax range
            m_nbTeams = UI::SliderInt("Nb Teams", m_nbTeams, MIN_TEAMS, MAX_TEAMS);
            m_nbTeams = Math::Max(MIN_TEAMS, Math::Min(m_nbTeams, MAX_TEAMS));  // manual values can be inputed outside minmax range
            UI::BeginDisabled(Time::Now < createRoomTimeout);
            if (UI::Button("Create Room" + idSuffix)) {
                createRoomTimeout = Time::Now + ROOM_TIMEOUT_MS;
                CreateRoom();
            }
            UI::EndDisabled();
            UI::Separator();
        }
        UI::AlignTextToFramePadding();
        m_joinCode = UI::InputText("Join Code" + idSuffix, m_joinCode, changed);
        UI::SameLine();
        if (UI::Button("Join##code" + idSuffix)) {
            UseJoinCode();
        }
        UI::Separator();
        UI::Dummy(vec2(0, 10));
        UI::Text("ROOMS:");
        UI::Dummy(vec2(0, 10));
        if (UI::BeginTable("rooms" + idSuffix, 4, UI::TableFlags::SizingStretchProp)) {
            UI::TableSetupColumn("Name");
            UI::TableSetupColumn("Player Limit");
            UI::TableSetupColumn("Nb Teams");
            UI::TableSetupColumn("");
            UI::TableHeadersRow();
            for (uint i = 0; i < rooms.Length; i++) {
                UI::TableNextRow();
                auto room = rooms[i];
                UI::TableNextColumn();
                UI::AlignTextToFramePadding();
                UI::Text(room.name);
                UI::TableNextColumn();
                UI::Text(tostring(room.n_players) + " / " + tostring(room.player_limit));
                UI::TableNextColumn();
                UI::Text(tostring(room.n_teams));
                UI::TableNextColumn();
                if (UI::Button("Join" + idSuffix + "_" + room.name)) {
                    JoinRoom(room.name);
                }
            }
            UI::EndTable();
        }
    }

    void JoinRoom(const string &in name) {
        auto pl = Json::Object();
        pl['name'] = name;
        parent.client.SendPayload("JOIN_ROOM", pl, CGF::Visibility::global);
    }

    void UseJoinCode() {
        auto pl = Json::Object();
        pl['code'] = m_joinCode;
        parent.client.SendPayload("JOIN_CODE", pl, CGF::Visibility::global);
        m_joinCode = "";
    }

    void CreateRoom() {
        auto pl = Json::Object();
        pl['name'] = m_roomName;
        pl['player_limit'] = m_playerLimit;
        pl['n_teams'] = m_nbTeams;
        auto vis = m_isPublic ? CGF::Visibility::global : CGF::Visibility::none;
        parent.client.SendPayload("CREATE_ROOM", pl, vis);
        m_roomName = "";
    }
}






ClientsTab@ clientsTab = ClientsTab();
// auto chatTab = ChatTab();
// auto lobbiesTab = LobbiesTab();

// Tab@[] Tabs = {clientsTab, chatTab, lobbiesTab};



#else
void RenderInterface() {}
void RenderMenu() {}
void Main() {}
#endif
}
