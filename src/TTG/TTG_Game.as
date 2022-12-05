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
        while (!IsShutdown && client.IsMainLobby) {
            client.JoinLobby("TicTacGo");
            joinAttemptCount += 1;
            if (joinAttemptCount > 5) {
                NotifyError("TTG: Unable to join lobby.");
                return;
            }
            sleep(2000);
        }
        while (!IsShutdown && client.IsInGameLobby) yield();
    }

    void SelfDestructLoop() {
        while (!IsShutdown) {
            yield();
            if (!MainWindowOpen) {
                startnew(TTG::NullifyGame);
            }
        }
    }

    void ResetGame() {
        ttg.ResetState();
    }

    void Render() {
        ttg.Render();
    }

    void RenderInterface() {
        UI::PushFont(hoverUiFont);
        if (!client.IsConnected) RenderConnecting();
        else if (!client.IsLoggedIn) RenderLoggingIn();
        else if (client.IsMainLobby) RenderJoiningGameLobby();
        else if (client.IsInGameLobby) RenderGameLobby();
        else if (client.IsInRoom) RenderRoom();
        else if (client.IsInGame) ttg.RenderInterface();
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
        auto pos = (UI::GetWindowContentRegionMax() - lastCenteredTextBounds) / 2.;
        UI::SetCursorPos(pos);
        UI::Text(msg);
        auto r = UI::GetItemRect();
        lastCenteredTextBounds.x = r.z;
        lastCenteredTextBounds.y = r.w;
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

    bool isCreatingRoom = false;
    string m_joinCode;
    bool showJoinCode = false;

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

        UI::Separator();
    }

    void OnClickCreateRoom() {
        isCreatingRoom = true;
    }

    void DrawRoomList() {
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
            if (UI::BeginTable("ttg-room-list-table", 4, UI::TableFlags::SizingStretchProp)) {
                UI::TableSetupColumn("Name");
                UI::TableSetupColumn("Player Limit");
                UI::TableSetupColumn("Nb Teams");
                UI::TableSetupColumn("");
                UI::TableHeadersRow();
                UI::ListClipper clipper(li.rooms.Length);
                while (clipper.Step()) {
                    for (uint i = clipper.DisplayStart; i < clipper.DisplayEnd; i++) {
                        DrawRoomListItem(li.rooms[i]);
                    }
                }
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
        UI::TableNextColumn();
        UI::Text(tostring(room.n_teams));
        UI::TableNextColumn();
        if (UI::Button("Join##" + room.name)) {
            client.JoinRoom(room.name);
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

    void RenderGameLobby() {
        if (BeginMainWindow()) {
            DrawLobbyHeader();
            DrawRoomList();
        }
        UI::End();
    }

    void RenderRoom() {
        isCreatingRoom = false;
        if (BeginMainWindow()) {

        }
        UI::End();
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
