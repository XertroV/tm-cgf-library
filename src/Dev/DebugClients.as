namespace Debug {
#if SIG_DEVELOPER
[Setting category="Debug" name="Show Clients Debug Window"]
bool S_ShowClientsDebugWindow = true;


Game::Client@[] allClients;
DebugClientWindow@[] allWindows;


void RemoveDebugClient(Game::Client@ client, DebugClientWindow@ window) {
    auto c = allClients.FindByRef(client);
    auto w = allWindows.FindByRef(window);
    if (c >= 0) @allClients[c] = null;
    if (w >= 0) @allWindows[w] = null;
    client.Shutdown();
}


void Main() {
    // clientsTab.CreateAndAddNewClient();
}


void Render() {
    for (uint i = 0; i < allWindows.Length; i++) {
        if (allWindows[i] is null) continue;
        allWindows[i].Render();
    }
}

void RenderInterface() {
    if (CurrentlyInMap) return;
    for (uint i = 0; i < allWindows.Length; i++) {
        if (allWindows[i] is null) continue;
        allWindows[i].RenderInterface();
    }
    if (!S_ShowClientsDebugWindow) return;
    UI::SetNextWindowSize(800, 450, UI::Cond::FirstUseEver);
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

/** Called whenever the mouse moves. `x` and `y` are the viewport coordinates.
*/
void OnMouseMove(int x, int y) {
    for (uint i = 0; i < allWindows.Length; i++) {
        allWindows[i].OnMouseMove(x, y);
    }
}

/** Called whenever a mouse button is pressed. `x` and `y` are the viewport coordinates.
*/
UI::InputBlocking OnMouseButton(bool down, int button, int x, int y) {
    bool blockClick = false;
    for (uint i = 0; i < allWindows.Length; i++) {
        if (allWindows[i].OnMouseButton(down, button, x, y) == UI::InputBlocking::Block)
            blockClick = true;
    }
    return blockClick ? UI::InputBlocking::Block : UI::InputBlocking::DoNothing;
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
    InRoomTab@ inRoomTab;
    InGameTab@ inGameTab;
    Tab@[] tabs;

    DebugClientWindow(Game::Client@ client) {
        @this.client = client;
        @lobbiesTab = LobbiesTab(this);
        @chatTab = ChatTab(this);
        @roomsTab = RoomsTab(this);
        @inRoomTab = InRoomTab(this);
        @inGameTab = InGameTab(this);
        tabs.InsertLast(chatTab);
        tabs.InsertLast(lobbiesTab);
        tabs.InsertLast(roomsTab);
        tabs.InsertLast(inRoomTab);
        tabs.InsertLast(inGameTab);
        windowVisible = true;
        client.AddMessageHandler("LOBBY_LIST", CGF::MessageHandler(lobbiesTab.OnLobbyList));
    }

    void Render() {
        for (uint i = 0; i < tabs.Length; i++) {
            tabs[i].Render();
        }
    }

    void RenderInterface() {
        if (!windowVisible) return;
        UI::SetNextWindowSize(850, 600, UI::Cond::FirstUseEver);
        if (UI::Begin(Meta::ExecutingPlugin().Name + " Client Debug: " + client.name, windowVisible)) {
            vec2 pos = UI::GetCursorPos();
            UI::Text("State: " + tostring(client.state));
            vec2 nextPos = UI::GetCursorPos();
            UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() - 100, 0));
            if (UI::Button("Disconnect")) {
                RemoveDebugClient(client, this);
            }
            UI::SetCursorPos(nextPos);
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

    void OnMouseMove(int x, int y) {
        for (uint i = 0; i < tabs.Length; i++) {
            tabs[i].OnMouseMove(x, y);
        }
    }

    UI::InputBlocking OnMouseButton(bool down, int button, int x, int y) {
        bool blockClick = false;
        for (uint i = 0; i < tabs.Length; i++) {
            if (tabs[i].OnMouseButton(down, button, x, y) == UI::InputBlocking::Block)
                blockClick = true;
        }
        return blockClick ? UI::InputBlocking::Block : UI::InputBlocking::DoNothing;
    }
}



void DrawRoomName(RoomInfo@ room) {
    string _name;
    if (room is null) _name = "?? unknown";
    else {
        auto nameParts = room.name.Split("##", 2);
        _name = nameParts.Length > 1 ? nameParts [0] + " \\$888" + nameParts[1] : nameParts[0];
    }
    UI::Text(_name);
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
                if (window is null) continue;
                window.client.DrawDebug();
                if (UI::Button((window.windowVisible ? "Hide" : "Show") + "##" + window.client.name)) {
                    window.windowVisible = !window.windowVisible;
                }
            }
        }
    }

    void CreateAndAddNewClient() {
        string name = LocalPlayersName + "-DC";
        if (S_LocalDev) {
            name = "DebugClient";
        }
        auto client = Game::Client(name + "-" + tostring(allClients.Length));
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

    void DrawTab() override
    {
        UI::BeginDisabled(parent.client.currScope >= 2);
        if (UI::BeginTabItem(tabName, TabFlags)) {
            DrawInner();
            UI::EndTabItem();
        }
        UI::EndDisabled();
    }

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
    int m_nbMapsReq = 9;
    int m_mapMinSecs = 15;
    int m_mapMaxSecs = 45;
    uint createRoomTimeout = 0;
    string m_joinCode;

    void DrawTab() override
    {
        UI::BeginDisabled(parent.client.currScope >= 2);
        if (UI::BeginTabItem(tabName, TabFlags)) {
            DrawInner();
            UI::EndTabItem();
        }
        UI::EndDisabled();
    }

    void DrawMapsNumMinMax() {
        if (UI::BeginTable("creat-room-maps-min-max", 5, UI::TableFlags::SizingStretchProp)) {
            UI::TableNextColumn();
            UI::AlignTextToFramePadding();
            TextSameLine("# Maps: ");
            m_nbMapsReq = UI::SliderInt("##nb-maps", m_nbMapsReq, 1, 100);

            UI::TableNextColumn();
            UI::Dummy(vec2(20, 0));

            UI::TableNextColumn();
            TextSameLine("Min Len (s): ");
            m_mapMinSecs = UI::InputInt("##min-len-s", m_mapMinSecs, 15);
            m_mapMinSecs = Math::Floor(m_mapMinSecs / 15.0) * 15.0;

            UI::TableNextColumn();
            UI::Dummy(vec2(20, 0));

            UI::TableNextColumn();
            TextSameLine("Max Len (s): ");
            m_mapMaxSecs = UI::InputInt("##max-len-s", m_mapMaxSecs, 15);
            m_mapMaxSecs = Math::Ceil(m_mapMaxSecs / 15.0) * 15.0;
            auto tmp = m_mapMinSecs;
            m_mapMinSecs = Math::Max(0, Math::Min(m_mapMinSecs, m_mapMaxSecs));
            m_mapMaxSecs = Math::Min(600, Math::Max(tmp, m_mapMaxSecs));

            UI::EndTable();
        }
    }

    void DrawInner() override {
        if (parent.client.lobbyInfo is null) return;
        auto li = parent.client.lobbyInfo;
        int nbRooms = li.n_rooms;
        auto rooms = li.rooms;
        string idSuffix = "##" + parent.client.name + "-" + li.name;
        UI::AlignTextToFramePadding();
        UI::Text("Lobby Name: " + li.name);
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
            DrawMapsNumMinMax();
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
                DrawRoomName(room);
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
        pl['maps_required'] = m_nbMapsReq;
        pl['min_secs'] = m_mapMinSecs;
        pl['max_secs'] = m_mapMaxSecs;
        auto vis = m_isPublic ? CGF::Visibility::global : CGF::Visibility::none;
        parent.client.SendPayload("CREATE_ROOM", pl, vis);
        m_roomName = "";
    }
}



class InGameTab : Tab {
    DebugClientWindow@ parent;
    TicTacGo@ ttg;

    InGameTab(DebugClientWindow@ parent) {
        @this.parent = parent;
        @this.ttg = TicTacGo(parent.client);
        @parent.client.gameEngine = this.ttg;
        super("Current Game");
    }

    void Reset() {
        this.ttg.ResetState();
    }

    int lastScope = -1;

    void Render() override {
        ttg.Render();
    }

    UI::InputBlocking OnMouseButton(bool down, int button, int x, int y) override {
        // return ttg.gui.OnMouseButton(down, button, x, y);
        return UI::InputBlocking::DoNothing;
    }

    void OnMouseMove(int x, int y) override {
        // ttg.gui.OnMouseMove(x, y);
    }

    void DrawTab() override
    {
        if (lastScope != parent.client.currScope) Reset();
        lastScope = parent.client.currScope;
        if (parent.client.currScope < 3) return;
        if (parent.client.gameInfoFull is null) return;
        // always draw window if this 'tab' is visible
        DrawInner();
        // if (UI::BeginTabItem(tabName, TabFlags)) {
        //     UI::EndTabItem();
        // }
    }

    void DrawInner() override {
        // UI::Text(parent.client.gameInfoFull.ToString());
        this.ttg.RenderInterface();
    }
}



class InRoomTab : Tab {
    DebugClientWindow@ parent;
    bool markReady = false;

    InRoomTab(DebugClientWindow@ parent) {
        @this.parent = parent;
        super("Current Room");
    }

    const string get_RoomName() {
        if (parent.client.roomInfo is null) return "";
        return parent.client.roomInfo.name;
    }

    void DrawTab() override
    {
        if (parent.client.currScope < 2) return;
        if (UI::BeginTabItem(tabName, TabFlags)) {
            DrawInner();
            UI::EndTabItem();
        }
    }

    void DrawInner() override {
        vec2 initPos = UI::GetCursorPos();
        UI::SetCursorPos(initPos + vec2(UI::GetWindowContentRegionWidth() - 60, 10));
        if (UI::Button("Leave##leave-room")) {
            parent.client.SendLeave();
        }
        UI::SetCursorPos(initPos);
        UI::Text("Name: ");
        UI::SameLine();
        DrawRoomName(parent.client.roomInfo);
        uint currNPlayers = parent.client.roomInfo.n_players;
        uint pLimit = parent.client.roomInfo.player_limit;
        uint nTeams = parent.client.roomInfo.n_teams;
        string joinCode = parent.client.roomInfo.join_code.GetOr("???");
        UI::Text("Players: " + currNPlayers + " / " + pLimit);
        UI::Text("N Teams: " + nTeams);
        DrawJoinCode(joinCode);

        DrawReadySection();

        UI::AlignTextToFramePadding();
        UI::Text("Select a team:");
        UI::SameLine();
        if (UI::Button(Icons::Refresh)) {
            parent.client.SendPayload("LIST_TEAMS");
        }
        DrawTeamSelection();
    }

    void DrawReadySection() {
        PaddedSep();
        auto pos = UI::GetCursorPos();

        if (parent.client.roomInfo.HasStarted) {
            UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() / 2. - 50., 0));
            if (UI::Button("Game started. Rejoin!")) {
                parent.client.SendPayload("JOIN_GAME_NOW");
            }
        } else {
            UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() / 3. - 35., 0));
            markReady = parent.client.GetReadyStatus(parent.client.clientUid);
            bool newReady = UI::Checkbox("Ready?##room-to-game", markReady);
            if (newReady != markReady)
                parent.client.MarkReady(newReady);
            markReady = newReady;

            UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() * 2. / 3. - 50., 0));
            if (parent.client.IsGameNotStarted) {
                UI::Text("Players Ready: " + parent.client.readyCount + " / " + parent.client.roomInfo.n_players);
            } else if (parent.client.IsGameStartingSoon) {
                UI::Text("Game Starting in " + Text::Format("%.1f", parent.client.GameStartingIn) + " (s)");
            } else if (parent.client.IsGameStarted) {
                UI::Text("Started");
            } else {
                UI::Text("Game State Unknown: " + tostring(parent.client.CurrGameState));
            }
        }

        PaddedSep();
    }

    bool jcHidden = true;
    void DrawJoinCode(const string &in jc) {
        UI::AlignTextToFramePadding();
        auto txt = jcHidden ? "- - - - - -" : jc;
        UI::Text("Join Code: ");
        UI::SameLine();
        auto jcPos = UI::GetCursorPos();
        UI::Text(txt);
        UI::SetCursorPos(jcPos + vec2(70, 0));
        if (UI::Button("Copy")) IO::SetClipboard(jc);
        UI::SameLine();
        UI::Dummy(vec2(20, 0));
        UI::SameLine();
        if (UI::Button("Reveal")) jcHidden = !jcHidden;
    }

    void DrawTeamSelection() {
        uint nTeams = parent.client.roomInfo.n_teams;
        if (UI::BeginTable("team selection", nTeams+2, UI::TableFlags::SizingStretchProp)) {
            UI::TableNextRow();
            UI::TableNextColumn(); // the first of the extra 2 columns; the second is implicit
            for (uint i = 0; i < nTeams; i++) {
                UI::TableNextColumn();
                UI::Text("Team: " + (i + 1));
            }

            UI::TableNextRow();
            UI::TableNextColumn();
            for (uint i = 0; i < nTeams; i++) {
                UI::TableNextColumn();
                if (UI::Button("Join Team " + (i + 1))) {
                    parent.client.SendPayload("JOIN_TEAM", JsonObject1("team_n", Json::Value(i)), CGF::Visibility::global);
                }
            }

            uint maxPlayersInAnyTeam = parent.client.roomInfo.player_limit;

            for (uint pn = 0; pn < maxPlayersInAnyTeam; pn++) {
                bool foundAnyPlayers = false;
                UI::TableNextRow();
                UI::TableNextColumn();
                for (uint i = 0; i < nTeams; i++) {
                    auto @team = parent.client.currTeams[i];
                    UI::TableNextColumn();
                    if (pn == 0 && team.Length == 0) {
                        UI::Text("No players in team " + (i + 1));
                    } else if (pn >= team.Length) {
                        continue;
                    } else {
                        // todo: draw player name
                        foundAnyPlayers = true;
                        string uid = team[pn];
                        bool ready = parent.client.GetReadyStatus(uid);
                        UI::Text((ready ? Icons::Check : Icons::Times) + " | " + parent.client.GetPlayerName(uid));
                    }
                }
            }

            UI::EndTable();
        }
    }
}



// todo
class AdminTab : Tab {
    DebugClientWindow@ parent;

    // todo: test permission system works

    AdminTab(DebugClientWindow@ parent) {
        @this.parent = parent;
        super("Admin (Lobby/Room)");
    }

    // if: scope => info => admins => incl this account => show tab
    // add/rm admins/mods, kick players
    // if room => change room settings?

    void DrawTab() override {
        // if (parent.client)
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
