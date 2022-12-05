// manage a full game
class TtgGame {
    Game::Client@ client;
    TicTacGo@ ttg;

    TtgGame() {
        @client = Game::Client();
        @ttg = TicTacGo(client);
        @client.gameEngine = ttg;
        startnew(CoroutineFunc(TtgLobbyLoop));
        startnew(CoroutineFunc(SelfDestructLoop));
    }

    bool get_IsShutdown() {
        return client is null || ttg is null;
    }

    void TtgLobbyLoop() {
        // wait for connection
        while (!IsShutdown && !client.IsConnected) yield();
        while (!IsShutdown && !client.IsLoggedIn) yield();
        yield();
        yield();
        uint joinAttemptCount = 0;
        warn("lobby loop waiting for main");
        warn("IsShutdown" + tostring(IsShutdown));
        if (!IsShutdown && client.IsMainLobby) {
            client.JoinLobby("TicTacGo");
            // joinAttemptCount += 1;
            // if (joinAttemptCount > 5) {
            //     NotifyError("TTG: Unable to join lobby.");
            //     return;
            // }
            // sleep(2000);
        }
        while (!IsShutdown && client.IsInGameLobby) yield();
        auto lastScope = client.currScope;
        while (!IsShutdown) {
            yield();
            if (lastScope != client.currScope) {
                lastScope = client.currScope;
                // if (lastScope == Game::Scope::InRoom)
                    // ttg.ResetState();
            }
        }
    }

    void SelfDestructLoop() {
        while (!IsShutdown) {
            yield();
            if (!MainWindowOpen) {
                startnew(TTG::NullifyGame);
            }
        }
    }

    // void ResetGame() {
    //     ttg.ResetState();
    // }

    void Render() {
        ttg.Render();
    }

    void RenderInterface() {
        if (CurrentlyInMap) return;
        UI::PushFont(hoverUiFont);
        if (!client.IsConnected) RenderConnecting();
        else if (!client.IsLoggedIn) RenderLoggingIn();
        else if (client.IsMainLobby) RenderJoiningGameLobby();
        else if (client.IsInGameLobby) RenderGameLobby();
        else if (client.IsInRoom) RenderRoom();
        else if (client.IsInGame) {
            if (ttg.GameInfo is null) RenderWaitingForGameInfo();
            else ttg.RenderInterface();
        }
        else {
            warn("Unknown client state!");
        }
        UI::PopFont();
    }

    protected bool MainWindowOpen = true; // set to false after deving so ppl have to open it

    protected bool BeginMainWindow() {
        // if (!MainWindowOpen) startnew(TTG::NullifyGame);
        UI::SetWindowSize(vec2(900, 650), UI::Cond::Appearing);
        return UI::Begin("Lobby - Tic Tac GO!", MainWindowOpen);
    }

    vec2 lastCenteredTextBounds = vec2(100, 20);
    void DrawCenteredText(const string &in msg) {
        UI::PushFont(mapUiFont);
        auto pos = (UI::GetWindowContentRegionMax() - lastCenteredTextBounds) / 2.;
        UI::SetCursorPos(pos);
        UI::Text(msg);
        auto r = UI::GetItemRect();
        lastCenteredTextBounds.x = r.z;
        lastCenteredTextBounds.y = r.w;
        UI::PopFont();
    }

    void RenderConnecting() {
        if (BeginMainWindow()) {
            DrawCenteredText("Connecting...");
        }
        UI::End();
    }

    void RenderLoggingIn() {
        if (BeginMainWindow()) {
            DrawCenteredText("Logging In...");
        }
        UI::End();
    }

    void RenderJoiningGameLobby() {
        if (BeginMainWindow()) {
            DrawCenteredText("Joining Lobby...");
        }
        UI::End();
    }

    void RenderWaitingForGameInfo() {
        if (BeginMainWindow()) {
            DrawCenteredText("Waiting for game info...");
        }
        UI::End();
    }

    bool isCreatingRoom = false;
    string m_joinCode;
    bool showJoinCode = false;

    void RenderGameLobby() {
        if (BeginMainWindow()) {
            if (isCreatingRoom) {
                DrawRoomCreation();
            } else {
                DrawLobbyHeader();
                DrawRoomList();
            }
        }
        UI::End();
    }

    void DrawLobbyHeader() {
        UI::PushFont(mapUiFont);
        // UI::Text("Lobby");
        if (UI::BeginTable("ttg-header", 3, UI::TableFlags::SizingFixedFit)) {
            UI::TableSetupColumn("l", UI::TableColumnFlags::WidthStretch);
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::AlignTextToFramePadding();
            UI::Text("Create or join a room.");
            UI::TableNextColumn();
            if (UI::Button("Create Room")) OnClickCreateRoom();
            UI::EndTable();
        }
        UI::PopFont();

        UI::Separator();

        UI::AlignTextToFramePadding();
        if (client.lobbyInfo is null) {
            UI::Text("Waiting for Lobby info...");
        } else {
            auto li = client.lobbyInfo;
            auto pos = UI::GetCursorPos();
            auto width = UI::GetWindowContentRegionWidth();
            UI::Text("Public Rooms: " + li.n_public_rooms);
            UI::SetCursorPos(pos + vec2(width / 3., 0));
            UI::AlignTextToFramePadding();
            UI::Text("Total Rooms: " + li.n_rooms);
            UI::SetCursorPos(pos + vec2(width / 3. * 2., 0));
            UI::AlignTextToFramePadding();
            UI::Text("Players in Lobby: " + li.n_clients);
        }

        UI::Separator();
        UI::Dummy(vec2(0, 4));

        UI::AlignTextToFramePadding();
        bool changed = false;
        UI::Text("Join Code: ");
        UI::SameLine();
        UI::SetNextItemWidth(Math::Max(150, UI::GetWindowContentRegionWidth() / 4));
        int flags = UI::InputTextFlags::EnterReturnsTrue;
        if (!showJoinCode) flags = flags | UI::InputTextFlags::Password;
        m_joinCode = UI::InputText("##Join Code", m_joinCode, changed, flags);
        UI::SameLine();
        if (UI::Button("Join##code") || changed) {
            client.JoinRoomViaCode(m_joinCode);
            m_joinCode = "";
        }
        UI::SameLine();
        showJoinCode = UI::Checkbox("Code Visible?", showJoinCode);

        UI::Dummy(vec2(0, 4));
        UI::Separator();
    }

    void OnClickCreateRoom() {
        isCreatingRoom = true;
    }

    void DrawRoomList() {
        UI::PushFont(mapUiFont);
        UI::AlignTextToFramePadding();
        UI::Text("Rooms:");
        UI::PopFont();

        UI::AlignTextToFramePadding();
        if (client.lobbyInfo is null) {
            UI::Text("Waiting for lobby info...");
            return;
        }
        auto li = client.lobbyInfo;
        if (li.rooms.Length == 0) {
            UI::Text("No public rooms open. Why don't you create one?");
            return;
        }
        if (UI::BeginChild("ttg-room-list")) {
            if (UI::BeginTable("ttg-room-list-table", 3, UI::TableFlags::SizingStretchProp)) {
                UI::TableSetupColumn("Name");
                UI::TableSetupColumn("Player Limit");
                // UI::TableSetupColumn("Nb Teams");
                UI::TableSetupColumn("");
                UI::TableHeadersRow();
                UI::ListClipper clipper(li.rooms.Length);
                while (clipper.Step()) {
                    for (uint i = clipper.DisplayStart; i < clipper.DisplayEnd; i++) {
                        DrawRoomListItem(li.rooms[i]);
                    }
                }
                UI::EndTable();
            }
        }
        UI::EndChild();
    }

    void DrawRoomListItem(RoomInfo@ room) {
        UI::TableNextRow();
        UI::TableNextColumn();
        UI::AlignTextToFramePadding();
        DrawRoomName(room);
        UI::TableNextColumn();
        UI::Text(tostring(room.n_players) + " / " + tostring(room.player_limit));
        // UI::TableNextColumn();
        // UI::Text(tostring(room.n_teams));
        UI::TableNextColumn();
        if (UI::Button("Join##" + room.name)) {
            client.JoinRoom(room.name);
        }
    }

    const string RoomNameText(RoomInfo@ room) {
        string _name;
        if (room is null) _name = "?? unknown";
        else {
            auto nameParts = room.name.Split("##", 2);
            _name = nameParts.Length > 1 ? nameParts [0] + " \\$888" + nameParts[1] : nameParts[0];
        }
        return _name;
    }

    void DrawRoomName(RoomInfo@ room) {
        UI::Text(RoomNameText(room));
    }

    bool DrawHeading1Button(const string &in heading, const string &in btnLabel) {
        UI::PushFont(mapUiFont);
        // UI::Text("Lobby");
        bool ret = false;
        if (UI::BeginTable("ttg-heading"+heading, 2, UI::TableFlags::SizingFixedFit)) {
            UI::TableSetupColumn("l", UI::TableColumnFlags::WidthStretch);
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::AlignTextToFramePadding();
            UI::Text(heading);
            UI::TableNextColumn();
            ret = UI::Button(btnLabel);
            UI::EndTable();
        }
        UI::PopFont();
        UI::Separator();
        return ret;
    }

    // consts for TTG
    int m_playerLimit = 2;
    int m_nbTeams = 2;
    int m_nbMapsReq = 9;
    // room vars
    string m_roomName = LocalPlayersName + "'s Room";
    bool m_isPublic = true;
    int m_mapMinSecs = 15;
    int m_mapMaxSecs = 45;
    // timeotu
    uint createRoomTimeout = 0;

    void DrawRoomCreation() {
        UI::PushFont(mapUiFont);
        // UI::Text("Lobby");
        if (UI::BeginTable("ttg-create-header", 3, UI::TableFlags::SizingFixedFit)) {
            UI::TableSetupColumn("l", UI::TableColumnFlags::WidthStretch);
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::AlignTextToFramePadding();
            UI::Text("Create a room.");
            UI::TableNextColumn();
            if (UI::Button("Back##from-create")) {
                isCreatingRoom = false;
            }
            UI::EndTable();
        }
        UI::PopFont();

        UI::Separator();
        bool changed = false;
        UI::AlignTextToFramePadding();
        UI::Text("Room Name:");
        UI::SameLine();
        m_roomName = UI::InputText("##Room Name", m_roomName, changed);
        m_isPublic = UI::Checkbox("Is Public?", m_isPublic);
        DrawMapsNumMinMax();
        UI::BeginDisabled(Time::Now < createRoomTimeout);
        if (UI::Button("Create Room")) {
            createRoomTimeout = Time::Now + ROOM_TIMEOUT_MS;
            CreateRoom();
        }
        UI::EndDisabled();
    }

    void DrawMapsNumMinMax() {
        UI::AlignTextToFramePadding();
        UI::Text("Map Length:");
        UI::AlignTextToFramePadding();
        TextSameLine("  Min Len (s): ");
        m_mapMinSecs = UI::InputInt("##min-len-s", m_mapMinSecs, 15);
        m_mapMinSecs = Math::Max(15, Math::Floor(m_mapMinSecs / 15.0) * 15.0);
        if (m_mapMaxSecs < m_mapMinSecs) {
            m_mapMaxSecs = m_mapMinSecs;
        }
        UI::AlignTextToFramePadding();
        TextSameLine("  Max Len (s): ");
        m_mapMaxSecs = UI::InputInt("##max-len-s", m_mapMaxSecs, 15);
        m_mapMaxSecs = Math::Ceil(m_mapMaxSecs / 15.0) * 15.0;
        if (m_mapMaxSecs < m_mapMinSecs) {
            m_mapMinSecs = m_mapMaxSecs;
        }
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
        client.SendPayload("CREATE_ROOM", pl, vis);
        m_roomName = LocalPlayersName + "'s Room";
    }

    void RenderRoom() {
        isCreatingRoom = false;
        if (BeginMainWindow()) {
            if (client.roomInfo is null) {
                DrawCenteredText("Waiting for room info...");
            } else {
                DrawRoomMain();
            }
        }
        UI::End();
    }

    void DrawRoomMain() {
        // vec2 initPos = UI::GetCursorPos();
        // UI::SetCursorPos(initPos + vec2(UI::GetWindowContentRegionWidth() - 75, 10));
        // if (UI::Button("Leave##leave-room")) {
        //     client.SendLeave();
        // }

        // UI::SetCursorPos(initPos);
        // UI::PushFont(mapUiFont);
        // UI::AlignTextToFramePadding();
        // // TextSameLine("Name:");
        // DrawRoomName(client.roomInfo);
        // UI::PopFont();

        if (DrawHeading1Button(RoomNameText(client.roomInfo), "Leave##leave-room")) {
            client.SendLeave();
        }

        uint currNPlayers = client.roomInfo.n_players;
        uint pLimit = client.roomInfo.player_limit;
        uint nTeams = client.roomInfo.n_teams;
        string joinCode = client.roomInfo.join_code.GetOr("???");
        UI::AlignTextToFramePadding();
        UI::Text("Players: " + currNPlayers + " / " + pLimit);
        // UI::AlignTextToFramePadding();
        // UI::Text("N Teams: " + nTeams);

        DrawJoinCode(joinCode);

        DrawReadySection();

        UI::AlignTextToFramePadding();
        UI::Text("Select a team:");
        UI::SameLine();
        if (UI::Button(Icons::Refresh)) {
            client.SendPayload("LIST_TEAMS");
        }
        DrawTeamSelection();
    }

    bool markReady = false;
    void DrawReadySection() {
        PaddedSep();
        auto pos = UI::GetCursorPos();

        if (client.roomInfo.HasStarted) {
            UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() / 2. - 50., 0));
            if (UI::Button("Game started. Rejoin!")) {
                client.SendPayload("JOIN_GAME_NOW");
            }
        } else {
            UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() / 3. - 35., 0));
            bool isInTeam = 0 <= client.PlayerIsOnTeam(client.clientUid);
            bool isReady = client.GetReadyStatus(client.clientUid);
            if (isInTeam || isReady) {
                markReady = client.GetReadyStatus(client.clientUid);
                bool newReady = UI::Checkbox("Ready?##room-to-game", markReady);
                if (newReady != markReady)
                    client.MarkReady(newReady);
                markReady = newReady;
            } else {
                UI::AlignTextToFramePadding();
                UI::Text("\\$fc3Join a Team");
            }

            UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() * 2. / 3. - 50., 0));
            UI::AlignTextToFramePadding();
            if (client.IsGameNotStarted) {
                UI::Text("Players Ready: " + client.readyCount + " / " + client.roomInfo.n_players);
            } else if (client.IsGameStartingSoon) {
                UI::Text("Game Starting in " + Text::Format("%.1f", client.GameStartingIn) + " (s)");
            } else if (client.IsGameStarted) {
                UI::Text("Started");
            } else {
                UI::Text("Game State Unknown: " + tostring(client.CurrGameState));
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
        UI::SetCursorPos(jcPos + vec2(100, 0));
        if (UI::Button("Copy")) IO::SetClipboard(jc);
        UI::SameLine();
        UI::Dummy(vec2(20, 0));
        UI::SameLine();
        if (UI::Button("Reveal")) jcHidden = !jcHidden;
    }

    void DrawTeamSelection() {
        uint nTeams = client.roomInfo.n_teams;
        UI::Dummy(vec2(20, 0));
        UI::SameLine();
        if (UI::BeginTable("team selection", nTeams, UI::TableFlags::SizingStretchSame)) {
            UI::TableNextRow();
            // UI::TableNextColumn(); // the first of the extra 2 columns; the second is implicit
            for (uint i = 0; i < nTeams; i++) {
                UI::TableNextColumn();
                UI::Text("Team: " + (i + 1));
            }

            UI::TableNextRow();
            // UI::TableNextColumn();
            for (uint i = 0; i < nTeams; i++) {
                UI::TableNextColumn();
                if (UI::Button("Join Team " + (i + 1))) {
                    client.SendPayload("JOIN_TEAM", JsonObject1("team_n", Json::Value(i)), CGF::Visibility::global);
                }
            }

            uint maxPlayersInAnyTeam = client.roomInfo.player_limit;

            for (uint pn = 0; pn < maxPlayersInAnyTeam; pn++) {
                bool foundAnyPlayers = false;
                UI::TableNextRow();
                // UI::TableNextColumn();
                for (uint i = 0; i < nTeams; i++) {
                    auto @team = client.currTeams[i];
                    UI::TableNextColumn();
                    if (pn == 0 && team.Length == 0) {
                        UI::Text("No players in team " + (i + 1));
                    } else if (pn >= team.Length) {
                        continue;
                    } else {
                        foundAnyPlayers = true;
                        string uid = team[pn];
                        bool ready = client.GetReadyStatus(uid);
                        UI::Text((ready ? Icons::Check : Icons::Times) + " | " + client.GetPlayerName(uid));
                    }
                }
            }

            UI::EndTable();
        }
    }
}

namespace TTG {
    TtgGame@ game = null;

    void RenderMenu() {
        bool selected = game !is null;
        if (UI::MenuItem("\\$e71" + Icons::Hashtag + "\\$z Tic Tac GO!", "", selected)) {
            if (selected) {
                NullifyGame();
            } else {
                startnew(InstantiateGame);
            }
        }
    }

    void InstantiateGame() {
        @game = TtgGame();
    }

    void NullifyGame() {
        if (game is null) {
            warn("NullifyGame called when it was already null!");
            return;
        }
        game.client.Shutdown();
        @game.client.gameEngine = null;
        @game.client = null;
        @game.ttg = null;
        @game = null;
    }

    void Render() {
        if (game !is null) {
            game.Render();
            game.RenderInterface();
        }
    }
}
