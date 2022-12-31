// manage a full game
class TtgGame {
    Game::Client@ client;
    TicTacGo@ ttg;
    bool hasPerms = false;
    bool rematchSetupActive = false;
    bool editGameOptsActive = false;
    bool showPatchNotes = false;
    string instId;

    TtgGame() {
        // required permissions
        hasPerms = Permissions::PlayLocalMap();
        if (hasPerms)
            startnew(CoroutineFunc(Initialize));
        else {
            NotifyError("You don't have the required permissions to play TTG. (PlayLocalMap)\n\nYou need standard or club access.");
        }
        instId = Crypto::RandomBase64(6);
    }

    void Initialize() {
        // this takes a while
        @client = Game::Client("TicTacGo");
        @ttg = TicTacGo(client);
        @client.gameEngine = ttg;
        @ttg.OnRematch = CoroutineFunc(this.OnRematch);
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
        if (IsShutdown) return;
        if (client.IsMainLobby) {
            client.JoinLobby("TicTacGo");
            startnew(CoroutineFunc(CheckLobbySoon));
        }
        while (!IsShutdown && client.IsInGameLobby) yield();
        if (IsShutdown) return;
        auto lastScope = client.currScope;
        while (!IsShutdown) {
            if (lastScope != client.currScope) {
                lastScope = client.currScope;
                rematchSetupActive = false;
                if (lastScope == Game::Scope::InRoom) {
                    // m_roomName = LocalPlayersName + "'s Room";
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
        bool overlayOpen = UI::IsOverlayShown();
        if (!overlayOpen && client.IsInGameLobby) return;
        if (showPatchNotes) RenderPatchNotesWindow();
        UI::PushFont(hoverUiFont);
        UI::PushStyleColor(UI::Col::FrameBg, vec4(.2, .2, .2, 1));
        if (!hasPerms) RenderNoPerms();
        else if (client is null || client.IsAuthenticating) RenderAuthenticating();
        else if (client.IsAuthError) RenderAuthError();
        else if (!client.IsConnected) RenderConnecting();
        else if (!client.IsLoggedIn) RenderLoggingIn();
        else if (client.IsMainLobby) RenderJoiningGameLobby();
        else if (client.IsInGameLobby) RenderGameLobby();
        else if (client.IsInRoom) {
            RenderRoom();
            if (editGameOptsActive) RenderEditGameOpts();
        }
        else if (client.IsInGame) {
            if (ttg.GameInfo is null) RenderWaitingForGameInfo();
            else if (client.roomInfo.use_club_room && !CurrentlyInMap && !ttg.stateObj.IsInClaimOrChallenge) RenderJoiningServer();
            else {
                ttg.RenderInterface();
                if (rematchSetupActive) RenderRematchSetup();
            }
        }
        else {
            RenderLoadingScreen("Unknown client state!", true);
            warn("Unknown client state!");
        }
        UI::PopStyleColor();
        UI::PopFont();
    }

    protected bool MainWindowOpen = true; // set to false after deving so ppl have to open it

    int DefaultLobbyWindowHeight = 750;
    int DefaultLobbyWindowWidth = 1000;

    protected bool BeginMainWindow() {
        // if (!MainWindowOpen) startnew(TTG::NullifyGame);
        UI::SetNextWindowSize(DefaultLobbyWindowWidth, DefaultLobbyWindowHeight, UI::Cond::FirstUseEver);
        bool ret = UI::Begin("Lobby - Tic Tac GO!##" + instId, MainWindowOpen);
        if (ret) UpdateLobbyWindowSizePos();
        return ret;
    }

    protected bool BeginRematchWindow() {
        UI::SetNextWindowSize(DefaultLobbyWindowWidth, DefaultLobbyWindowHeight, UI::Cond::Appearing);
        bool ret = UI::Begin("TTG! Rematch Set Up##" + instId, rematchSetupActive);
        return ret;
    }

    protected bool BeginEditGameOptsWindow() {
        UI::SetNextWindowSize(DefaultLobbyWindowWidth, DefaultLobbyWindowHeight, UI::Cond::Appearing);
        bool ret = UI::Begin("TTG! Edit Game Options##" + instId, editGameOptsActive);
        return ret;
    }

    void RenderPatchNotesWindow() {
        UI::SetNextWindowSize(DefaultLobbyWindowWidth, DefaultLobbyWindowHeight, UI::Cond::Appearing);
        if (UI::Begin("CGF / TTG! Patch Notes##" + instId, showPatchNotes)) {
            Render_Settings_Changelog();
        }
        UI::End();
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

    void RenderLoadingScreen(const string &in loadingMsg, bool flatline = false) {
        if (BeginMainWindow()) {
            DrawCenteredText(loadingMsg);
        }
        UI::End();
        RenderHeartbeatPulse(lobbyWindowPos + lobbyWindowSize / 2., lobbyWindowSize / 2. * vec2(1, flatline ? 0.0001 : 1.));
    }

    void RenderAuthenticating() {
        RenderLoadingScreen(Icons::Heartbeat + "  Authenticating... (~3s)");
    }

    void RenderAuthError() {
        RenderLoadingScreen(Icons::Heartbeat + "  Authentication Error.\nTry restarting the plugin.", true);
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

    void RenderJoiningServer() {
        RenderLoadingScreen(Icons::Hashtag + "  Joining Server...");
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

    void RenderRematchSetup() {
        if (!rematchSetupActive) return;
        if (BeginRematchWindow()) {
            DrawRoomCreation();
        }
        UI::End();
    }

    void RenderEditGameOpts() {
        if (!editGameOptsActive) return;
        if (BeginEditGameOptsWindow()) {
            if (DrawHeading1Button("Edit Game Options", "Back")) {
                editGameOptsActive = false;
            }
            UI::AlignTextToFramePadding();
            UI::Text("\\$eb1Note: these values are not autopopulated with the room's existing settings.");
            DrawSetGameOptions(true);
            UI::Separator();
            if (UI::Button("Save Game Options")) {
                editGameOptsActive = false;
                UpdateGameOpts();
            }
        }
        UI::End();
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
            float cols = 4.;
            auto li = client.lobbyInfo;
            auto pos = UI::GetCursorPos();
            auto width = UI::GetWindowContentRegionWidth();
            UI::Text("Public Rooms: " + li.n_public_rooms);
            UI::SetCursorPos(pos + vec2(width / cols, 0));
            UI::AlignTextToFramePadding();
            UI::Text("Total Rooms: " + li.n_rooms);
            UI::SetCursorPos(pos + vec2(width / cols * 2., 0));
            UI::AlignTextToFramePadding();
            UI::Text("Players in Lobby: " + li.n_clients);
            UI::SetCursorPos(pos + vec2(width / cols * 3., 0));
            if (UI::Button("Patch Notes")) {
                showPatchNotes = true;
            }
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
        return nameParts.Length > 1 ? ColoredString(nameParts[0]) + " \\$888" + nameParts[1] : ColoredString(nameParts[0]);
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

    void OnRematch() {
        rematchSetupActive = true;
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
    CGF::MaxDifficulty m_maxDifficulty = CGF::MaxDifficulty::Intermediate;
    CGF::MapSelection m_mapsType = CGF::MapSelection::RandomWithFilter;
    string m_mapPackID = "";
    // game stuff
    Json::Value@ gameOptions = DefaultTtgGameOptions();
    int m_opt_finishesToWin = 4;
    // timeotu
    uint createRoomTimeout = 0;
    bool m_singlePlayer = false;
    bool m_useClubRoom = false;

    void DrawRoomCreation() {
        if (DrawHeading1Button("Create a room.", "Back##from-create")) {
            isCreatingRoom = false;
        }

        if (UI::BeginTable("room-creation-opts", 2, UI::TableFlags::SizingStretchSame)) {
            UI::TableNextRow();
            UI::TableNextColumn();

            DrawMainRoomOptions();
            UI::Separator();
            DrawMapOptionsInput();

            UI::TableNextColumn();

            // update modes and single player based on ticking the single player box
            if (m_singlePlayer) gameOptions['mode'] = 1;
            DrawSetGameOptions();
            if (m_singlePlayer && int(gameOptions['mode']) != 1) m_singlePlayer = false;

            UI::EndTable();
        }

        UI::Separator();

        UI::PushFont(mapUiFont);
        UI::BeginDisabled(Time::Now < createRoomTimeout);
        if (UI::Button("Create Room")) {
            createRoomTimeout = Time::Now + ROOM_TIMEOUT_MS;
            rematchSetupActive = false;
            CreateRoom();
        }
        UI::EndDisabled();
        UI::PopFont();
    }

    void DrawMainRoomOptions() {
        UI::Text(Highlight(">>  Room Options:"));

        bool changed = false;

        Indent(2);
        UI::AlignTextToFramePadding();
        UI::Text("Room Name:");
        UI::SameLine();
        m_roomName = UI::InputText("##Room Name", m_roomName, changed);

        Indent(2);
        m_isPublic = UI::Checkbox("Is Public?", m_isPublic);

        Indent(2);
        m_singlePlayer = UI::Checkbox("Single Player Game?", m_singlePlayer);
        AddSimpleTooltip("Note: this will auto-disable the room being public.");
        if (m_singlePlayer) {
            m_isPublic = false;
        }

        // don't show the checkbox here if the user isn't able to create an activity in a club,
        // since we're sort of doing that on their behalf.
        if (Permissions::CreateActivity()) {
            Indent(2);
            m_useClubRoom = UI::Checkbox("Play on a server instead of locally. (\\$fe1" + Icons::ExclamationTriangle + " Experimental\\$z)", m_useClubRoom);
            AddSimpleTooltip("Each round, each player's client will auto-vote on the next map.\nIf that fails, manually voting to go to the correct map should fix things.");
        }

    }

    void DrawMapOptionsInput() {
        UI::AlignTextToFramePadding();
        UI::Text(Highlight(">>  Map Options:"));
        DrawMapSelectionType();
        if (m_mapsType == CGF::MapSelection::RandomWithFilter) {
            DrawMapsNumMinMax();
            DrawMapsMaxDifficulty();
        } else if (m_mapsType == CGF::MapSelection::MapPack) {
            DrawMapPackInput();
        } else {
            Indent(2);
            UI::AlignTextToFramePadding();
            UI::Text("Map Source: " + tostring(m_mapsType));
        }
    }

    void DrawMapSelectionType() {
        Indent(2);
        UI::AlignTextToFramePadding();
        UI::Text("Selection Type:");
        UI::SameLine();
        if (UI::BeginCombo("##map-selection-type", CGF::MapSelectionStr(m_mapsType))) {
            DrawMapSelectionTypeSelectable(CGF::MapSelection::RandomWithFilter);
            DrawMapSelectionTypeSelectable(CGF::MapSelection::MapPack);
            DrawMapSelectionTypeSelectable(CGF::MapSelection::TrackOfTheDay);
            DrawMapSelectionTypeSelectable(CGF::MapSelection::RoyalTraining);
            UI::EndCombo();
        }
    }

    void DrawMapSelectionTypeSelectable(CGF::MapSelection ms) {
        if (UI::Selectable(CGF::MapSelectionStr(ms), m_mapsType == ms)) {
            m_mapsType = ms;
        }
    }

    void DrawMapPackInput() {
        Indent(2);
        UI::AlignTextToFramePadding();
        UI::Text("Map Pack ID:");
        UI::SameLine();
        m_mapPackID = UI::InputText("##map-pack-input", m_mapPackID);
        if (!IsIntStr(m_mapPackID)) {
            Indent(2);
            UI::Text("\\$fe1Invalid map pack ID (should be an integer).");
        }
    }

    void DrawMapsNumMinMax() {
        UI::AlignTextToFramePadding();
        Indent(2);
        TextSameLine("Min Len (s): ");
        m_mapMinSecs = UI::InputInt("##min-len-s", m_mapMinSecs, 15);
        m_mapMinSecs = Math::Max(15, int(Math::Floor(m_mapMinSecs / 15.0)) * 15);
        if (m_mapMaxSecs < m_mapMinSecs) {
            m_mapMaxSecs = m_mapMinSecs;
        }
        UI::AlignTextToFramePadding();
        Indent(2);
        TextSameLine("Max Len (s): ");
        m_mapMaxSecs = UI::InputInt("##max-len-s", m_mapMaxSecs, 15);
        m_mapMaxSecs = int(Math::Ceil(m_mapMaxSecs / 15.0)) * 15;
        if (m_mapMaxSecs < m_mapMinSecs) {
            m_mapMinSecs = m_mapMaxSecs;
        }
    }

    void DrawMapsMaxDifficulty() {
        Indent(2);
        UI::AlignTextToFramePadding();
        TextSameLine("Max. Difficulty: ");
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

    void DrawSetGameOptions(bool isEditingGameOpts = false) {
        // UI::Separator();
        UI::AlignTextToFramePadding();
        UI::Text(Highlight(">>  Game Options"));

        Indent(2);
        auto currMode = TTGMode(int(gameOptions['mode']));
        UI::AlignTextToFramePadding();
        UI::Text("Mode:");
        UI::SameLine();
        if (UI::BeginCombo("##go-mode", tostring(currMode))) {
            if (!isEditingGameOpts)
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
            uint upperLimit = 64;
            m_playerLimit = UI::SliderInt("##-playerlimit", m_playerLimit, 3, upperLimit);
        }

        if (currMode == TTGMode::BattleMode) {
            // draw room size dragger
            UI::AlignTextToFramePadding();
            Indent(2);
            UI::Text("Finishes to Win:");
            UI::SameLine();
            m_opt_finishesToWin = UI::SliderInt("##-finishes-to-win", m_opt_finishesToWin, 1, m_playerLimit / 2);
            m_opt_finishesToWin = Math::Min(m_playerLimit / 2, m_opt_finishesToWin);
        }

#if DEV
        DrawScoreConditionGameOpt();
#endif

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
            UI::AlignTextToFramePadding();
            Indent(2);
            UI::Text("Auto DNF Seconds: ");
            UI::SameLine();
            m_autoDnfSecs = UI::SliderInt("##-autodnfsecs", m_autoDnfSecs, 1, 60);
        }

        Indent(2);
        JsonCheckbox("1st round for center square?", gameOptions, "1st_round_for_center", true);
        AddSimpleTooltip("Instead of a random player going first, the 1st round is for the center square.\nThe winner claims it always. The loser gets the next turn.");

        Indent(2);
        JsonCheckbox("Cannot pick last round's square?", gameOptions, "cannot_repick", true);
        AddSimpleTooltip("When a square is successfully claimed/challenged,\nit cannot be immediately re-challenged.");

        Indent(2);
        JsonCheckbox("Reveal maps?", gameOptions, "reveal_maps", false);
        AddSimpleTooltip("Instead of maps being hidden, you can\nsee every map from the start of the game.");

        // todo, remember to add to draw function & default opts

        // Indent(2);
        // JsonCheckbox("Alternate turn sequence?", gameOptions, "alt_turn_sequence", false);
        // AddSimpleTooltip("Each team takes 2 turns instead of 1. e.g., 1,1,2,2,...");

        // Indent(2);
        // JsonCheckbox("", gameOptions, "alt_turn_sequence", false);
        // AddSimpleTooltip("Each team takes 2 turns instead of 1. e.g., 1,1,2,2,...");

        // hmm, think we need to add game-mode stuff for this.
        // Indent();
        // JsonCheckbox("Give-up = DNF?", gameOptions, "give_up_is_dnf", false);
        // AddSimpleTooltip("");
    }

    void DrawScoreConditionGameOpt() {
        auto currMapGoal = MapGoal(int(gameOptions['map_goal']));
        Indent(2);
        UI::AlignTextToFramePadding();
        TextSameLine("Map Goal:");
        auto clicked = UI::BeginCombo("##map-goal", tostring(currMapGoal));
        AddSimpleTooltip("What must players achieve in order to score?\n(Note: the TTG timer doesn't reset.)");
        if (clicked) {
            DrawMapGoalSelectable(MapGoal::Finish, currMapGoal);
            DrawMapGoalSelectable(MapGoal::Bronze, currMapGoal);
            DrawMapGoalSelectable(MapGoal::Silver, currMapGoal);
            DrawMapGoalSelectable(MapGoal::Gold, currMapGoal);
            DrawMapGoalSelectable(MapGoal::Author, currMapGoal);
            UI::EndCombo();
        }
    }

    bool DrawMapGoalSelectable(MapGoal goal, MapGoal curr) {
        bool clicked = UI::Selectable(tostring(goal), goal == curr);
        if (clicked) {
            gameOptions['map_goal'] = int(goal);
        }
        return clicked;
    }

    const string ModeDescription(TTGMode mode) {
        switch (mode) {
            case TTGMode::SinglePlayer:
                return "Play as both players. When you claim or challenge a square and finish the map, the active position (challenger) will get the win by 100ms. If you DNF, the defender will get the win. This is useful for testing out what the game is like without needing another player.";
            case TTGMode::Standard:
                return "Standard 2 player game. Every time a square is claimed or challenged, the active player (challenger) must win a head-to-head race to claim the square. Ties resolve in favor of the inactive player (defender).";
            case TTGMode::Teams:
                return "2 teams, scored like in match making / ranked. For a total of X players, 1st place gets X points, 2nd place X-1 points, etc. The team with more points wins the round. The first player on each team is that team's leader. Each Leader is the only player to input tic-tac-toe moves, but all players race. If teams are uneven, the smaller team gets an advantage.";
            case TTGMode::BattleMode:
                return "Up to 64 players over 2 teams. The first team where X players finish wins the round. The first player on each team is the leader. Each Leader is the only player to input tic-tac-toe moves, but all players race. If not enough players finish, the team with more points wins the round. If the score is equal, the defending team wins. 'Finishes to win' auto-adjusts if it's too high.";
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
        pl['use_club_room'] = m_useClubRoom;
        auto vis = (m_isPublic && !singlePlayer) ? CGF::Visibility::global : CGF::Visibility::none;

        if (m_mapsType == CGF::MapSelection::MapPack) {
            pl['map_pack'] = Text::ParseInt(m_mapPackID);
        } else if (m_mapsType == CGF::MapSelection::RoyalTraining) {
            pl['map_pack'] = 1566;
        } else if (m_mapsType == CGF::MapSelection::TrackOfTheDay) {
            pl['use_totd'] = true;
        } else if (pl.HasKey('map_pack')) {
            pl.Remove('map_pack');
        }

        if (singlePlayer) {
            pl['n_teams'] = 1;
            pl['player_limit'] = 1;
        } else if (isStd) {
            pl['player_limit'] = 2;
        }

        client.SendPayload("CREATE_ROOM", pl, vis);
    }

    void UpdateGameOpts() {
        auto pl = Json::Object();
        auto mode = TTGMode(int(gameOptions['mode']));
        if (mode == TTGMode::Standard) {
            m_playerLimit = 2;
        }
        pl['player_limit'] = m_playerLimit; // might be > 2 for teams or battle mode
        gameOptions['auto_dnf'] = m_AutoDnfEnabled ? m_autoDnfSecs : -1;
        gameOptions['finishes_to_win'] = m_opt_finishesToWin;
        pl['game_opts'] = gameOptions;
        client.SendPayload("UPDATE_GAME_OPTS", pl, CGF::Visibility::global);
    }

    void RenderRoom() {
        isCreatingRoom = false;
        if (client.roomInfo is null) {
            RenderLoadingScreen("Waiting for room info...");
        } else {
            if (BeginMainWindow()) {
                DrawRoomMain();
            }
            UI::End();
            RenderLobbyChatWindow("Room");
        }
    }

    bool teamsLocked = false;

    void DrawRoomMain() {
        string heading = RoomNameText(client.roomInfo);
        heading += "  \\$z (" + (client.roomInfo.is_public ? "Public" : "Private") + ")";
        if (DrawHeading1Button(heading, "Leave##leave-room")) {
            client.SendLeave();
        }

        auto roomInfo = client.roomInfo;
        uint currNPlayers = roomInfo.n_players;
        uint pLimit = roomInfo.player_limit;
        uint nTeams = roomInfo.n_teams;
        string joinCode = roomInfo.join_code.GetOr("???");
        UI::AlignTextToFramePadding();
        string mapsStatus = roomInfo.maps_loaded ? "Loaded." : "Loading...";
        UI::Text("Players: " + currNPlayers + " / " + pLimit + ".   Maps " + mapsStatus);
        if (client.HasLoadError) {
            UI::AlignTextToFramePadding();
            UI::TextWrapped("\\$fe1 " + Icons::ExclamationTriangle + " Load Error! Code: " + client.LoadErrorStatusCode + " | \\$z " + client.LoadErrorMessage);
        }
        if (client.LastRoomPreparationStatus.Length > 0) {
            UI::AlignTextToFramePadding();
            UI::TextWrapped("\\$999Room Setup Status: \\$z" + client.LastRoomPreparationStatus);
        }
        if (roomInfo.use_club_room && !HasJoinLinkPermissions()) {
            UI::AlignTextToFramePadding();
            UI::TextWrapped("\\$fe1 " + Icons::ExclamationTriangle + " Permissions Error!\\$z You need the permissions PlayPublicClubRoom and PlayPrivateActivity to play TTG on a server.");
        }
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
        string hostVer = roomInfo.game_opts.Get('game_version', '0.1.20 or earlier');
        string myVersion = Meta::ExecutingPlugin().Version;
        if (hostVer != myVersion) {
            UI::AlignTextToFramePadding();
            UI::TextWrapped("\\$fe1" + Icons::ExclamationTriangle + "  Game version mismatch. Your version: " + myVersion + ". Room version: " + hostVer + ".");
            AddSimpleTooltip("You are running a version of the game different from the person who created this room.\nYou might not be able to finish the game due to version mismatch.");
        }
        if (TtgCollapsingHeader("Game Details")) {
            if (roomInfo.use_club_room) {
                Indent(2);
                UI::Text("Play on a Server: True (" + (roomInfo.join_link.Length > 0 ? "Got Join Link" : "Awaiting Join Link") + ")");
            }
            Indent(2);
            if (roomInfo.map_pack >= 0) {
                UI::Text("Maps: from Map Pack #" + roomInfo.map_pack);
            } else if (roomInfo.use_totd) {
                UI::Text("Maps: Track of the Day");
            } else {
                UI::Text("Maps: between " + roomInfo.min_secs + " and " + roomInfo.max_secs + " s long, and a maximum difficulty of " + roomInfo.max_difficulty + ".");
            }
            auto go = roomInfo.game_opts;
            auto currMode = TTGMode(Text::ParseInt(go['mode']));
            Indent(2);
            UI::Text("Mode: " + tostring(currMode));
            if (currMode == TTGMode::BattleMode) {
                Indent(4);
                UI::Text("Finishes to Win: " + string(go.Get('finishes_to_win', '1')));
            }

#if DEV
            auto currGoal = MapGoal(Text::ParseInt(go.Get('map_goal', '0')));
            Indent(2);
            UI::Text("Map Goal: " + tostring(currGoal));
#endif

            Indent(2);
            UI::Text("Records Enabled: " + string(go.Get('enable_records', 'False')));

            Indent(2);
            auto auto_dnf = Text::ParseInt(go.Get('auto_dnf', '-1'));
            UI::Text("Auto DNF: " + (auto_dnf > 0 ? tostring(auto_dnf) + " seconds" : "Disabled"));

            Indent(2);
            UI::Text("1st round for center square: " + string(go.Get('1st_round_for_center', 'False')));

            Indent(2);
            UI::Text("Cannot repick: " + string(go.Get('cannot_repick', 'False')));

            Indent(2);
            UI::Text("Reveal maps: " + string(go.Get('reveal_maps', 'False')));

            // remember to add to default options, too
        }
    }

    bool markReady = false;
    void DrawReadySection() {
        PaddedSep();
        auto pos = UI::GetCursorPos();

        if (client.roomInfo.HasStarted) {
            UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() / 2. - 100., 0));
            if (client.roomInfo.maps_loaded) {
                if (UI::Button("Game started. Rejoin!")) {
                    client.SendPayload("JOIN_GAME_NOW");
                }
            } else {
                UI::Text("Waiting for maps...");
            }
        } else {
            bool isAdmin = client.IsPlayerAdminOrMod(client.clientUid);
            auto nCols = isAdmin ? 5 : 3;
            if (UI::BeginTable("ttg-ready,force,status", nCols, UI::TableFlags::SizingStretchSame)) {
                UI::TableSetupColumn("l");
                UI::TableSetupColumn("ready");
                UI::TableSetupColumn("status");
                if (isAdmin)
                    UI::TableSetupColumn("admin-force-start");
                // UI::TableSetupColumn("r");

                UI::TableNextRow();
                UI::TableNextColumn();
                // ready button
                UI::TableNextColumn();
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

                // ready status
                UI::TableNextColumn();
                UI::AlignTextToFramePadding();
                if (client.IsGameNotStarted) {
                    UI::Text("Players Ready: " + client.readyCount + " / " + client.roomInfo.n_players);
                } else if (client.IsGameStartingSoon) {
                    UI::Text("Game Starting in " + Text::Format("%.1f", client.GameStartingIn) + " (s)");
                } else if (client.IsGameStarted) {
                    UI::Text(client.roomInfo.maps_loaded ? "Started" : "Waiting for maps...");
                } else {
                    UI::Text("Game State Unknown: " + tostring(client.CurrGameState));
                }

                // admin
                if (isAdmin) {
                    UI::TableNextColumn();
                    if (UI::Button("Force Start")) {
                        client.SendPayload("FORCE_START");
                    }
                    UI::TableNextColumn();
                    bool isSinglePlayer = 1 == Text::ParseInt(client.roomInfo.game_opts.Get('mode', '2'));
                    if (!isSinglePlayer && UI::Button("Edit Game Options")) {
                        editGameOptsActive = true;
                    }
                }

                // UI::TableNextColumn();
                UI::EndTable();
            }
            // UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() / 3. - 35., 0));


            // UI::SetCursorPos(pos + vec2(UI::GetWindowContentRegionWidth() * 2. / 3. - 50., 0));
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
    go['1st_round_for_center'] = true;
    go['cannot_repick'] = true;
    go['reveal_maps'] = false;
    go['game_version'] = Meta::ExecutingPlugin().Version;
    go['map_goal'] = int(MapGoal::Finish);

    return go;
}

enum MapGoal {
    Finish = 0, Bronze = 1, Silver, Gold, Author
}
