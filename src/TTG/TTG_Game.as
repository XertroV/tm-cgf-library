// manage a full game
class TtgGame {
    Game::Client@ client;
    TicTacGo@ ttg;
    bool hasPerms = false;

    TtgGame() {
        // required permissions
        hasPerms = Permissions::PlayLocalMap();
        if (hasPerms)
            startnew(CoroutineFunc(Initialize));
        else {
            NotifyError("You don't have the required permissions to play TTG. (PlayLocalMap)\n\nYou need standard or club access.");
        }
    }

    void Initialize() {
        // this takes a while
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
        if (!IsShutdown && client.IsMainLobby) {
            client.JoinLobby("TicTacGo");
            startnew(CoroutineFunc(CheckLobbySoon));
        }
        while (!IsShutdown && client.IsInGameLobby) yield();
        if (IsShutdown) return;
        auto lastScope = client.currScope;
        while (!IsShutdown) {
            if (lastScope != client.currScope) {
                lastScope = client.currScope;
                if (lastScope == Game::Scope::InRoom) {
                    m_roomName = LocalPlayersName + "'s Room";
                    teamsLocked = false;
                }
            }
            yield();
        }
    }

    void CheckLobbySoon() {
        sleep(3000);
        if (!IsShutdown && client.IsMainLobby) {
            client.JoinLobby("TicTacGo");
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
        if (hasPerms && ttg !is null)
            ttg.Render();
    }

    void RenderInterface() {
        if (CurrentlyInMap) return;
        UI::PushFont(hoverUiFont);
        if (!hasPerms) RenderNoPerms();
        else if (client is null || client.IsAuthenticating) RenderAuthenticating();
        else if (!client.IsConnected) RenderConnecting();
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

    int DefaultLobbyWindowHeight = 650;

    protected bool BeginMainWindow() {
        // if (!MainWindowOpen) startnew(TTG::NullifyGame);
        UI::SetNextWindowSize(900, DefaultLobbyWindowHeight, UI::Cond::FirstUseEver);
        bool ret = UI::Begin("Lobby - Tic Tac GO!", MainWindowOpen);
        if (ret) UpdateLobbyWindowSizePos();
        return ret;
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

    void RenderNoPerms() {
        if (BeginMainWindow()) {
            DrawCenteredText(Icons::ExclamationTriangle + "  Standard or Club access required.");
        }
        UI::End();
    }

    void RenderLoadingScreen(const string &in loadingMsg) {
        if (BeginMainWindow()) {
            DrawCenteredText(loadingMsg);
        }
        UI::End();
        RenderHeartbeatPulse(lobbyWindowPos + lobbyWindowSize / 2., lobbyWindowSize / 2.);
    }

    void RenderAuthenticating() {
        RenderLoadingScreen(Icons::Heartbeat + "  Authenticating... (~3s)");
    }

    void RenderConnecting() {
        RenderLoadingScreen(Icons::Users + "  Connecting...");
    }

    void RenderLoggingIn() {
        RenderLoadingScreen(Icons::Users + "  Logging In...");
    }

    void RenderJoiningGameLobby() {
        RenderLoadingScreen(Icons::Hashtag + "  Joining Lobby...");
    }

    void RenderWaitingForGameInfo() {
        RenderLoadingScreen(Icons::Hashtag + "  Waiting for game info...");
    }

    bool isCreatingRoom = false;
    string m_joinCode;
    bool showJoinCode = false;

    vec2 lobbyWindowSize = vec2(900, DefaultLobbyWindowHeight);
    vec2 lobbyWindowPos = vec2(200, 200);

    void UpdateLobbyWindowSizePos() {
        lobbyWindowSize = UI::GetWindowSize();
        lobbyWindowPos = UI::GetWindowPos();
    }

    void RenderGameLobby() {
        if (BeginMainWindow()) {
            // UpdateLobbyWindowSizePos();
            if (isCreatingRoom) {
                DrawRoomCreation();
            } else {
                DrawLobbyHeader();
                DrawRoomList();
            }
        }
        UI::End();
        RenderLobbyChatWindow();
    }

    int lobbyChatWindowFlags = UI::WindowFlags::NoResize;
        // | UI::WindowFlags::None;

    /**
     * scope name is intended to be 'Lobby' or 'Room'
     */
    void RenderLobbyChatWindow(const string &in scopeName = "Lobby") {
        if (S_TTG_HideLobbyChat) return;
        bool isOpen = !S_TTG_HideLobbyChat;
        UI::SetNextWindowSize(300, int(lobbyWindowSize.y), UI::Cond::Always);
        UI::SetNextWindowPos(int(lobbyWindowPos.x + lobbyWindowSize.x + 20), int(lobbyWindowPos.y), UI::Cond::Always);
        if (UI::Begin(scopeName + " Chat##" + client.clientUid, isOpen, lobbyChatWindowFlags)) {
            ttg.DrawChat(false);
        }
        UI::End();
        S_TTG_HideLobbyChat = !isOpen;
    }

    void DrawLobbyHeader() {
        if (DrawHeading1Button("Create or join a room.", "Create Room")) {
            OnClickCreateRoom();
        }

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
        string rmVisBtn = S_TTG_HideRoomNames ? "Show " : "Hide ";
        if (DrawSubHeading1Button("Rooms:", rmVisBtn + "Names")) {
            S_TTG_HideRoomNames = !S_TTG_HideRoomNames;
        }

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
                    for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; i++) {
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
        if (room is null)
            return "?? unknown";
        auto nameParts = room.name.Split("##", 2);
        return nameParts.Length > 1 ? nameParts[0] + " \\$888" + nameParts[1] : nameParts[0];
    }

    const string RoomNameNonce(RoomInfo@ room) {
        if (room is null)
            return "?? unknown";
        auto nameParts = room.name.Split("##", 2);
        return nameParts.Length > 1 ? "--" + " \\$888" + nameParts[1] : "--";
    }

    void DrawRoomName(RoomInfo@ room) {
        UI::Text(S_TTG_HideRoomNames ? RoomNameNonce(room) : RoomNameText(room));
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
    CGF::MaxDifficulty m_maxDifficulty = CGF::MaxDifficulty::Expert;
    // game stuff
    Json::Value@ gameOptions = DefaultTtgGameOptions();
    int m_opt_finishesToWin = 1;
    // timeotu
    uint createRoomTimeout = 0;
    bool m_singlePlayer = false;

    void DrawRoomCreation() {

        if (DrawHeading1Button("Create a room.", "Back##from-create")) {
            isCreatingRoom = false;
        }

        bool changed = false;
        UI::AlignTextToFramePadding();
        UI::Text("Room Name:");
        UI::SameLine();
        m_roomName = UI::InputText("##Room Name", m_roomName, changed);
        m_isPublic = UI::Checkbox("Is Public?", m_isPublic);
        m_singlePlayer = UI::Checkbox("Single Player Game?", m_singlePlayer);
        AddSimpleTooltip("Note: this will auto-disable the room being public.");
        if (m_singlePlayer) {
            m_isPublic = false;
        }

        DrawMapsNumMinMax();
        DrawMapsMaxDifficulty();

        // update modes and single player based on ticking the single player box
        if (m_singlePlayer) gameOptions['mode'] = 1;
        DrawSetGameOptions();
        if (m_singlePlayer && int(gameOptions['mode']) != 1) m_singlePlayer = false;

        UI::BeginDisabled(Time::Now < createRoomTimeout);
        if (UI::Button("Create Room")) {
            createRoomTimeout = Time::Now + ROOM_TIMEOUT_MS;
            CreateRoom();
        }
        UI::EndDisabled();
    }

    void DrawMapsNumMinMax() {
        UI::AlignTextToFramePadding();
        UI::Text("Map Constraints:");
        UI::AlignTextToFramePadding();
        Indent();
        TextSameLine("Min Len (s): ");
        m_mapMinSecs = UI::InputInt("##min-len-s", m_mapMinSecs, 15);
        m_mapMinSecs = Math::Max(15, int(Math::Floor(m_mapMinSecs / 15.0)) * 15);
        if (m_mapMaxSecs < m_mapMinSecs) {
            m_mapMaxSecs = m_mapMinSecs;
        }
        UI::AlignTextToFramePadding();
        Indent();
        TextSameLine("Max Len (s): ");
        m_mapMaxSecs = UI::InputInt("##max-len-s", m_mapMaxSecs, 15);
        m_mapMaxSecs = int(Math::Ceil(m_mapMaxSecs / 15.0)) * 15;
        if (m_mapMaxSecs < m_mapMinSecs) {
            m_mapMinSecs = m_mapMaxSecs;
        }
    }

    void DrawMapsMaxDifficulty() {
        Indent();
        UI::AlignTextToFramePadding();
        TextSameLine("Maximum Difficulty: ");
        if (UI::BeginCombo("##max-difficulty", tostring(m_maxDifficulty))) {
            DrawDifficultySelectable(CGF::MaxDifficulty::Beginner);
            DrawDifficultySelectable(CGF::MaxDifficulty::Intermediate);
            DrawDifficultySelectable(CGF::MaxDifficulty::Advanced);
            DrawDifficultySelectable(CGF::MaxDifficulty::Expert);
            DrawDifficultySelectable(CGF::MaxDifficulty::Lunatic);
            DrawDifficultySelectable(CGF::MaxDifficulty::Impossible);
            UI::EndCombo();
        }
    }

    void DrawDifficultySelectable(CGF::MaxDifficulty d) {
        if (UI::Selectable(tostring(d), m_maxDifficulty == d)) {
            m_maxDifficulty = d;
        }
    }

    bool DrawModeSelectable(TTGMode mode, TTGMode curr) {
        bool clicked = UI::Selectable(tostring(mode), mode == curr);
        if (clicked) {
            gameOptions['mode'] = int(mode);
        }
        if (UI::IsItemHovered()) {
            DrawModeTooltip(mode);
        }
        return clicked;
    }

    void DrawModeTooltip(TTGMode mode) {
        UI::BeginTooltip();
        auto pos = UI::GetCursorPos();
        UI::Dummy(vec2(lobbyWindowSize.x / 3., 0));
        UI::SetCursorPos(pos);
        UI::SetNextItemWidth(lobbyWindowSize.x / 3.);
        UI::TextWrapped("\\$ddd" + ModeDescription(mode));
        UI::EndTooltip();
    }

    bool m_AutoDnfEnabled = false;
    int m_autoDnfSecs = 30;

    void DrawSetGameOptions() {
        UI::AlignTextToFramePadding();
        if (TtgCollapsingHeader("Game Options")) {
            Indent(2);
            auto currMode = TTGMode(int(gameOptions['mode']));
            UI::AlignTextToFramePadding();
            UI::Text("Mode:");
            UI::SameLine();
            if (UI::BeginCombo("##go-mode", tostring(currMode))) {
                DrawModeSelectable(TTGMode::SinglePlayer, currMode);
                DrawModeSelectable(TTGMode::Standard, currMode);
                if (DrawModeSelectable(TTGMode::Teams, currMode)) {
                    m_playerLimit = 6;
                }
                if (DrawModeSelectable(TTGMode::BattleMode, currMode)) {
                    m_playerLimit = 16;
                }
                UI::EndCombo();
            }
            if (UI::IsItemHovered()) {
                DrawModeTooltip(currMode);
            }

            if (int(currMode) > 2) {
                // draw room size dragger
                UI::AlignTextToFramePadding();
                Indent(2);
                UI::Text("Player Limit:");
                UI::SameLine();
                // can bump this up to 64 but lets be conservative for the moment
                uint upperLimit = 32;
                m_playerLimit = UI::SliderInt("##-playerlimit", m_playerLimit, 3, upperLimit);
            }

            if (currMode == TTGMode::BattleMode) {
                // draw room size dragger
                UI::AlignTextToFramePadding();
                Indent(2);
                UI::Text("N Finishes to Win:");
                UI::SameLine();
                m_opt_finishesToWin = UI::SliderInt("##-finishes-to-win", m_opt_finishesToWin, 1, m_playerLimit / 2);
            }

            Indent(2);
            JsonCheckbox("Enable records?", gameOptions, "enable_records", false);
            AddSimpleTooltip("Enable the records UI element when playing maps. (Default: disabled)");

            // Indent();
            // JsonCheckbox("Allow stealing maps?", gameOptions, "can_steal", true);
            // AddSimpleTooltip("Even after a map is claimed, it's not safe.\nYour opponent can challenge you for any of your claimed maps, and vice versa.");

            Indent(2);
            m_AutoDnfEnabled = UI::Checkbox("Auto DNF?", m_AutoDnfEnabled);
            AddSimpleTooltip("Players will automatically DNF after X seconds.");

            if (m_AutoDnfEnabled) {
                Indent(2);
                UI::Text("Auto DNF Seconds: ");
                UI::SameLine();
                m_autoDnfSecs = UI::SliderInt("##-autodnfsecs", m_autoDnfSecs, 1, 60);
            }

            // hmm, think we need to add game-mode stuff for this.
            // Indent();
            // JsonCheckbox("Give-up = DNF?", gameOptions, "give_up_is_dnf", false);
            // AddSimpleTooltip("");
        }
    }

    const string ModeDescription(TTGMode mode) {
        switch (mode) {
            case TTGMode::SinglePlayer:
                return "Play as both players. When you claim or challenge a square and finish the map, the active position (challenger) will get the win by 100ms. If you DNF, the defender will get the win. This is useful for testing out what the game is like without needing another player.";
            case TTGMode::Standard:
                return "Standard 2 player game. Every time a square is claimed or challenged, the active player (challenger) must win a head-to-head race to claim the square. Ties resolve in favor of the inactive player (defender).";
            case TTGMode::Teams:
                return "2 teams, scored like in match making / ranked. For a total of N players, 1st place gets N points, 2nd place N-1 points, etc. The team with more points wins the round.";
            case TTGMode::BattleMode:
                return "Up to 64 players over 2 teams. The best time from each team is used each round. Similar to Standard mode. Auto-DNF turned on is recommended.";
        }
        return "Unknown mode. D:";
    }

    void CreateRoom() {
        auto pl = Json::Object();
        auto mode = TTGMode(int(gameOptions['mode']));
        bool singlePlayer = int(mode) == 1;
        bool isStd = int(mode) == 2;
        bool isBattleMode = mode == TTGMode::BattleMode;
        gameOptions['auto_dnf'] = m_AutoDnfEnabled ? m_autoDnfSecs : -1;
        if (isBattleMode) gameOptions['finishes_to_win'] = m_opt_finishesToWin;

        pl['name'] = m_roomName;
        pl['player_limit'] = m_playerLimit; // might be > 2 for teams or battle mode
        pl['n_teams'] = 2;
        pl['maps_required'] = m_nbMapsReq;
        pl['min_secs'] = m_mapMinSecs;
        pl['max_secs'] = m_mapMaxSecs;
        pl['max_difficulty'] = int(m_maxDifficulty);
        pl['game_opts'] = gameOptions;
        auto vis = (m_isPublic && !singlePlayer) ? CGF::Visibility::global : CGF::Visibility::none;

        if (singlePlayer) {
            pl['n_teams'] = 1;
            pl['player_limit'] = 1;
        } else if (isStd) {
            pl['player_limit'] = 2;
        }

        client.SendPayload("CREATE_ROOM", pl, vis);
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
        RenderLobbyChatWindow("Room");
    }

    bool teamsLocked = false;

    void DrawRoomMain() {
        if (DrawHeading1Button(RoomNameText(client.roomInfo), "Leave##leave-room")) {
            client.SendLeave();
        }

        auto roomInfo = client.roomInfo;
        uint currNPlayers = roomInfo.n_players;
        uint pLimit = roomInfo.player_limit;
        uint nTeams = roomInfo.n_teams;
        string joinCode = roomInfo.join_code.GetOr("???");
        UI::AlignTextToFramePadding();
        UI::Text("Players: " + currNPlayers + " / " + pLimit);
        // UI::AlignTextToFramePadding();
        // UI::Text("N Teams: " + nTeams);

        DrawJoinCode(joinCode);

        DrawGameDetailsText();

        DrawReadySection();

        UI::AlignTextToFramePadding();
        UI::Text("Select a team:");
        UI::SameLine();
        if (UI::Button(Icons::Refresh)) {
            client.SendPayload("LIST_TEAMS");
        }
        UI::SameLine();
        if (UI::Button(teamsLocked ? Icons::Lock : Icons::Unlock)) {
            teamsLocked = !teamsLocked;
        }
        AddSimpleTooltip("Disable the 'join team' buttons so you don't accidentally press one and change team.\nRecommended if you are a team leader.");
        DrawTeamSelection(teamsLocked);
    }

    void DrawGameDetailsText() {
        auto roomInfo = client.roomInfo;
        if (TtgCollapsingHeader("Game Details")) {
            Indent(2);
            UI::Text("Maps: between " + roomInfo.min_secs + " and " + roomInfo.max_secs + " s long, and a maximum difficulty of " + roomInfo.max_difficulty + ".");
            auto go = roomInfo.game_opts;
            auto currMode = TTGMode(Text::ParseInt(go['mode']));
            Indent(2);
            UI::Text("Mode: " + tostring(currMode));
            Indent(2);
            UI::Text("Records Enabled: " + string(go['enable_records']));
            Indent(2);
            auto auto_dnf = Text::ParseInt(go.Get('auto_dnf', '-1'));
            UI::Text("Auto DNF: " + (auto_dnf > 0 ? tostring(auto_dnf) + " seconds" : "Disabled"));
        }
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

    void DrawTeamSelection(bool disabled = false) {
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
                UI::BeginDisabled(disabled);
                if (UI::Button("Join Team " + (i + 1))) {
                    client.SendPayload("JOIN_TEAM", JsonObject1("team_n", Json::Value(i)), CGF::Visibility::global);
                }
                UI::EndDisabled();
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




Json::Value@ DefaultTtgGameOptions() {
    auto go = Json::Object();
    go['mode'] = int(TTGMode::Standard);
    go['enable_records'] = false;
    go['auto_dnf'] = -1;

    return go;
}
