enum TTGSquareState {
    Unclaimed = -1,
    Player1 = 0,
    Player2 = 1
}

const int AUTO_DNF_TIMEOUT = 10000;
// DNFs are signaled with this time. It's 24hrs + 999ms;
const int DNF_TIME = 86400999;
const int DNF_TEST = 86400000;

UI::Font@ boardFont = UI::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", 50., -1, -1, true, true, true);
UI::Font@ mapUiFont = UI::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", 35, -1, -1, true, true, true);
UI::Font@ hoverUiFont = UI::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", 20, -1, -1, true, true, true);
int nvgFontMessage = nvg::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf");
// int nvgFontTimer = nvg::LoadFont("fonts/MontserratMono-SemiBoldItalic.ttf");
int nvgFontTimer = nvg::LoadFont("fonts/OswaldMono-Regular.ttf");
// int defaultNvgFont = nvg::LoadFont("DroidSans.ttf", true, true);

// update IsInAGame if these are added to
enum TTGGameState {
    // proceeds to waiting for move
    PreStart
    // can proceed to claim (immediate) or challenge (proceed to InChallenge)
    , WaitingForMove
    , InClaim
    , InChallenge
    , GameFinished
}



class TicTacGo : Game::Engine {
    Game::Client@ client;
    TicTacGoUI@ gui;
    TTGSquareState[][] boardState;
    bool[][] boardMapKnown;
    string idNonce;

    TTGGameState state = TTGGameState::PreStart;

    TTGSquareState IAmPlayer;
    TTGSquareState TheyArePlayer;
    TTGSquareState ActivePlayer;
    bool IsSinglePlayerGame;
    TTGSquareState WinningPlayer;
    int2[] WinningSquares;
    string[] playerUids;

    ChallengeResultState@ challengeResult;

    Json::Value@[] incomingEvents;
    TTGGameEvent@[] gameLog;
    uint turnCounter = 0;

    TicTacGo(Game::Client@ client, bool setRandomNonce = false) {
        if (setRandomNonce)
            idNonce = tostring(Math::Rand(0, 99999999));
        @this.client = client;
        client.AddMessageHandler("PLAYER_LEFT", CGF::MessageHandler(MsgHandler_PlayerEvent));
        client.AddMessageHandler("PLAYER_JOINED", CGF::MessageHandler(MsgHandler_PlayerEvent));
        client.AddMessageHandler("LOBBY_LIST", CGF::MessageHandler(MsgHandler_Ignore));
        @challengeResult = ChallengeResultState();
        ResetState();
        // @gui = TicTacGoUI(this);
    }

    void ResetState() {
        trace("TTG State Reset!");
        // reset board
        turnCounter = 0;
        gameLog.Resize(0);
        boardState.Resize(3);
        boardMapKnown.Resize(3);
        challengeResult.Reset();
        for (uint x = 0; x < boardState.Length; x++) {
            boardState[x].Resize(3);
            boardMapKnown[x].Resize(3);
            for (uint y = 0; y < boardState[x].Length; y++) {
                boardState[x][y] = TTGSquareState::Unclaimed;
                boardMapKnown[x][y] = false;
            }
        }
        state = TTGGameState::PreStart;
        ActivePlayer = TTGSquareState::Unclaimed;
        WinningPlayer = TTGSquareState::Unclaimed;
    }

    void PrettyPrintBoardState() {
        string b = "\n";
        for (uint row = 0; row < 3; row++) {
            b += "\n";
            for (uint col = 0; col < 3; col++) {
                auto s = GetSquareState(col, row);
                b += s == TTGSquareState::Unclaimed ? "-" : (s == TTGSquareState::Player1 ? "1" : "2");
            }
        }
        print(b);
    }

    bool MsgHandler_PlayerEvent(Json::Value@ j) {
        if (!client.IsInGame) return true;
        string type = j['type'];
        bool addToLog = type == "PLAYER_LEFT" || type == "PLAYER_JOINED";
        if (addToLog) gameLog.InsertLast(TTGGameEvent_PlayerEvent(type, j['payload']));
        return true;
    }

    bool MsgHandler_Ignore(Json::Value@ j) {
        return true;
    }

    vec2 get_framePadding() {
        return UI::GetStyleVarVec2(UI::StyleVar::FramePadding);
    };

    GameInfoFull@ get_GameInfo() {
        return client.gameInfoFull;
    }

    TTGSquareState get_InactivePlayer() const {
        return ActivePlayer == IAmPlayer ? TheyArePlayer : IAmPlayer;
    }

    string OpponentsName = "??";
    // string ActivePlayersName = "??";

    const string get_ActivePlayersName() {
        string uid;
        if (ActivePlayer == TTGSquareState::Unclaimed) {
            return "";
        }
        if (ActivePlayer == IAmPlayer) {
            return client.GetPlayerName(client.clientUid);
        } else {
            return OpponentsName;
        }
        return client.GetPlayerName(uid);
    }

    // const string get_OpponentsName() {
    //     return client.GetPlayerName(GameInfo.teams[int(TheyArePlayer)][0]);
    // }

    const string get_MyName() {
        // return client.GetPlayerName(GameInfo.teams[int(IAmPlayer)][0]);
        return client.GetPlayerName(client.clientUid);
    }

    const string GetPlayersName(TTGSquareState p) {
        return (p == IAmPlayer) ? MyName : OpponentsName;
        // return client.GetPlayerName(GameInfo.teams[int(p)][0]);
    }

    string setPlayersRes = "";

    void SetPlayers() {
        while (GameInfo is null) {
            log_trace("SetPlayers found null game info, yielding");
            yield();
        }
        ActivePlayer = TTGSquareState(GameInfo.team_order[0]);
        IsSinglePlayerGame = GameInfo.team_order.Length == 1;
        string myUid = client.clientUid;
        bool isPlayer1 = GameInfo.teams[0][0] == myUid;
        string oppUid = IsSinglePlayerGame ? myUid : GameInfo.teams[isPlayer1 ? 1 : 0][0];
        if (isPlayer1) {
            IAmPlayer = TTGSquareState::Player1;
            TheyArePlayer = TTGSquareState::Player2;
        } else {
            IAmPlayer = TTGSquareState::Player2;
            TheyArePlayer = TTGSquareState::Player1;
        }
        print("ActivePlayer (start): " + tostring(ActivePlayer));
        setPlayersRes = "Active=" + tostring(ActivePlayer) + "; " + "IAmPlayer=" + tostring(IAmPlayer);
        for (uint i = 0; i < GameInfo.players.Length; i++) {
            auto item = GameInfo.players[i];
            if (item.uid == oppUid) {
                OpponentsName = item.username;
                break;
            }
        }
        if (OpponentsName == "??") {
            warn("Could not find opponents name.");
        }
        gameLog.InsertLast(TTGGameEvent_StartingPlayer(ActivePlayer, ActivePlayersName));
    }

    void OnGameStart() {
        trace("On game start!");
        MM::setMenuPage("/empty");
        ResetState();
        SetPlayers();
        state = TTGGameState::WaitingForMove;
        startnew(CoroutineFunc(GameLoop));
    }

    void OnGameEnd() {
        // gameFinished = true;
        state = TTGGameState::GameFinished;
        MM::setMenuPage("/home");
    }

    TTGSquareState GetSquareState(int col, int row) const {
        // trace_dev("xy: " + col + ", " + row);
        return boardState[col][row];
    }

    void SetSquareState(int col, int row, TTGSquareState newState) {
        trace("set (" + col + ", " + row + ") to " + tostring(newState));
        boardState[col][row] = newState;
        // PrettyPrintBoardState();
    }

    void MarkSquareKnown(int col, int row) {
        boardMapKnown[col][row] = true;
    }

    bool SquareKnown(int col, int row) {
        return boardMapKnown[col][row];
    }

    bool SquareOwnedByMe(int col, int row) const {
        return IAmPlayer == boardState[col][row];
    }

    bool SquareOwnedByThem(int col, int row) const {
        return TheyArePlayer == boardState[col][row];
    }

    void Render() {
        if (!CurrentlyInMap) {
            // gui.Render();
            if (IsInAGame)
                RenderBackgroundGoneNotice();
            return;
        }
        // print("render? " + challengeStartTime + ", gt: " + currGameTime);
        if (challengeStartTime < 0) return;
        if (currGameTime < 0) return;
        if (!challengeRunActive) return;
        RenderChatWindow();
        // print("render going ahead");
        auto duration = challengeEndTime - challengeStartTime;
        // string sign = duration < 0 ? "-" : "";
        // duration = Math::Abs(duration);
        nvg::Reset();
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Bottom);
        nvg::FontFace(nvgFontTimer);
        auto fs = Draw::GetHeight() * 0.06;
        nvg::FontSize(fs);
        auto textPos = vec2(Draw::GetWidth() / 2., Draw::GetHeight() * 0.98);
        vec2 offs = vec2(fs, fs) * 0.05;
        NvgTextWShadow(textPos, offs.x, TimeFormat(duration), vec4(1, 1, 1, 1));
        if (challengeResult.HasResultFor(TheyArePlayer)) {
            nvg::TextAlign(nvg::Align::Center | nvg::Align::Top);
            nvg::FontFace(nvgFontMessage);
            textPos *= vec2(1, 0.03);
            fs *= .7;
            nvg::FontSize(fs);
            offs *= .7;
            auto oppTime = challengeResult.GetResultFor(TheyArePlayer, DNF_TIME);
            auto timeLeft = oppTime + AUTO_DNF_TIMEOUT - duration;
            auto col = vec4(1, .5, 0, 1);
            string msg = oppTime > DNF_TEST ? OpponentsName + " DNF'd"
                : OpponentsName + "'s Time: " + Time::Format(challengeResult.GetResultFor(TheyArePlayer));
            NvgTextWShadow(textPos, offs.x, msg, col);
            if (duration > oppTime) {
                textPos += vec2(0, fs);
                NvgTextWShadow(textPos, offs.x, "You lost.", col);
                // textPos += vec2(0, fs);
                // NvgTextWShadow(textPos, offs.x, "Auto DNFing in " + TimeFormat(timeLeft, true, false), col);
            }

            // nvg::FillColor(vec4(0, 0, 0, 1));
            // nvg::Text(textPos + offs, );
            // nvg::FillColor(vec4(.8, .4, 0, 1));
            // nvg::Text(textPos, OpponentsName + "'s Time: " + Time::Format(challengeResult.GetResultFor(TheyArePlayer)));


        }
    }

    int chatWindowFlags = UI::WindowFlags::NoTitleBar
        | UI::WindowFlags::None;

    void RenderChatWindow() {
        if (S_TTG_HideChat) return;
        bool isOpen = !S_TTG_HideChat;
        UI::SetNextWindowSize(400, 250, UI::Cond::FirstUseEver);
        if (UI::Begin("chat window" + idNonce, isOpen, chatWindowFlags)) {
            // draw a child so buttons work
            if (UI::BeginChild("chat window child" + idNonce)) {
                DrawChat();
            }
            UI::EndChild();
        }
        UI::End();
        // only change this when we close the window, tho there's no title bar atm so mb moot
        if (!isOpen)
            S_TTG_HideChat = !isOpen;
    }

    void RenderBackgroundGoneNotice() {
        nvg::TextAlign(nvg::Align::Right | nvg::Align::Middle);
        nvg::FontFace(nvgFontMessage);
        nvg::FontSize(25);
        nvg::FillColor(vec4(1, 1, 1, 1));
        string msg = "The menu will return to normal after the game has concluded. This prevents a script error when using the PlayMap command. (Manually change via the CFG menu item.)";
        float w = Draw::GetWidth() / 3.;
        auto offs = nvg::TextBoxBounds(w, msg);
        nvg::TextBox(vec2(Draw::GetWidth(), Draw::GetHeight()) - vec2(25, 0) - offs, w, msg);
    }

    // we call this from render, so it will always show even if OP Interface hidden.
    // that's b/c there's no real reason to hide the game window when you're actively in a game, and it autohides in a map
    void RenderInterface() {
        if (ActivePlayer == TTGSquareState::Unclaimed) return;
        UI::SetNextWindowSize(Draw::GetWidth() * 0.5, Draw::GetHeight() * 0.6, UI::Cond::FirstUseEver);
        UI::PushFont(hoverUiFont);
        if (UI::Begin("Tic Tac GO!##" + idNonce)) {
            // LogPlayerStartTime();
            // Tic Tac Toe interface
            auto available = UI::GetContentRegionAvail();
            auto midColSize = available * vec2(.5, 1) - UI::GetStyleVarVec2(UI::StyleVar::FramePadding);
            midColSize.x = Math::Min(midColSize.x, midColSize.y);
            auto lrColSize = (available - vec2(midColSize.x, 0)) * vec2(.5, 1) - UI::GetStyleVarVec2(UI::StyleVar::FramePadding) * 2.;
            // player 1
            DrawLeftCol(lrColSize);
            UI::SameLine();
            // game board
            DrawMiddleCol(midColSize);
            UI::SameLine();
            // player 2
            DrawRightCol(lrColSize);
        }
        UI::End();
        UI::PopFont();
        DrawChallengeWindow();
    }

    // player 1 col
    void DrawLeftCol(vec2 size) {
        if (UI::BeginChild("ttg-p1", size, true)) {
            DrawPlayer(TTGSquareState::Player1);
            UI::Dummy(vec2(0, 15));
            DrawPlayer(TTGSquareState::Player2);
            UI::Dummy(vec2(0, 15));
            DrawChat();
        }
        UI::EndChild();
    }

    // player 2 col
    void DrawRightCol(vec2 size) {
        if (UI::BeginChild("ttg-p2", size, true)) {
            DrawGameLog();
        }
        UI::EndChild();
    }

    // game col
    void DrawMiddleCol(vec2 size) {
        if (UI::BeginChild("ttg-game", size, true)) {
            DrawTicTacGoBoard(size - (framePadding * 2.));
        }
        UI::EndChild();
    }

    void DrawGameLog() {
        UI::PushFont(hoverUiFont);
        if (UI::BeginTable("game log", 2, UI::TableFlags::SizingFixedFit)) {
            UI::TableSetupColumn("gl", UI::TableColumnFlags::WidthStretch);
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::AlignTextToFramePadding();
            UI::Text("Game Log");
            UI::TableNextColumn();
            if (UI::Button("Leave Game")) {
                if (IsGameFinished)
                    client.SendLeave();
                client.SendLeave();
            }
            UI::EndTable();
        }
        UI::Separator();
        if (UI::BeginChild("##game-log-child")) {
            if (gameLog.IsEmpty()) {
                UI::Text("No moves yet.");
            } else {
                for (int i = gameLog.Length - 1; i >= 0; i--) {
                    gameLog[i].Draw();
                    UI::Dummy(vec2(0, 8));
                }
            }
        }
        UI::EndChild();
        UI::PopFont();
    }

    bool IsPlayerConnected(TTGSquareState player) {
        return (IsSinglePlayerGame && player == TTGSquareState::Player2) || client.currentPlayers.Exists(GameInfo.teams[player][0]);
    }

    void DrawPlayer(TTGSquareState player) {
        if (ActivePlayer == TTGSquareState::Unclaimed) return;
        auto team = int(player);
        auto playerNum = team + 1;
        UI::PushFont(hoverUiFont);
        UI::Text(IconForPlayer(player) + " -- Player " + playerNum);
        auto nameCol = "\\$" + (ActivePlayer == player ? "4b1" : "999");
        string name = IAmPlayer == player ? MyName : OpponentsName;
        UI::Text(nameCol + name);
        if (!IsPlayerConnected(player)) {
            UI::SameLine();
            UI::Text("\\$ea4 (Disconnected)");
        }
        UI::PopFont();
        if (player == TTGSquareState::Player2) {
#if DEV
            // UI::Dummy(vec2(0, 15));
            // UI::Text("Game State: " + tostring(state));
            // UI::Text("Team Order: " + GameInfo.team_order[0] + ", " + GameInfo.team_order[1]);
            // UI::Text("Active: " + tostring(ActivePlayer));
            // UI::Text("Inactive: " + tostring(InactivePlayer));
            // UI::Text("IAmPlayer: " + tostring(IAmPlayer));
            // UI::Text("TheyArePlayer: " + tostring(TheyArePlayer));
            // UI::TextWrapped(setPlayersRes);
#endif
            if (IsGameFinished) {
                UI::Dummy(vec2(0, 15));
                UI::PushFont(hoverUiFont);
                if (UI::Button("Leave##game")) {
                    // once for game, once for room
                    client.SendLeave();
                    client.SendLeave();
                }
                UI::PopFont();
            }
        }
    }

    vec4 lastWinMsgSize = vec4(0, 0, 100, 30);

    void DrawTicTacGoBoard(vec2 size) {
        size.y -= UI::GetFrameHeightWithSpacing() * 2.;
        auto side = Math::Min(size.x, size.y);
        vec2 boardSize = vec2(side, side);
        vec2 buttonSize = (boardSize / 3.) - (framePadding * 2.);
        float xPad = size.x > size.y ? (size.x - side) / 2. : framePadding.x;
        float yPad = size.x < size.y ? (size.y - side) / 2. : 0.;
        if (UI::BeginTable("ttg-table-status", 3, UI::TableFlags::SizingStretchSame)) {
            UI::TableSetupColumn("l", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("m", UI::TableColumnFlags::WidthFixed);
            UI::TableSetupColumn("r", UI::TableColumnFlags::WidthStretch);
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::TableNextColumn();
            UI::PushFont(hoverUiFont);
            if (IsMyTurn)
                UI::Text(HighlightWin("Your Turn!"));
            else
                UI::Text(ActivePlayersName + "'s Turn");
            UI::PopFont();
            UI::EndTable();
        }
        UI::Dummy(vec2(0, yPad));
        UI::Dummy(vec2(xPad, 0));
        UI::SameLine();
        auto boardTL = UI::GetCursorPos();
        if (UI::BeginTable("ttg-table", 3, UI::TableFlags::SizingFixedSame)) {
            for (uint row = 0; row < 3; row++) {
                UI::TableNextRow();
                for (uint col = 0; col < 3; col++) {
                    UI::TableNextColumn();
                    DrawTTGSquare(col, row, buttonSize);
                }
            }
            UI::EndTable();
        }
        if (IsGameFinished) {
            string winMsg = "Winner:\n" + ActivePlayersName;
            UI::PushFont(mapUiFont);
            vec2 pos = boardTL + (boardSize * .5) - vec2(10, 0);
            pos.x -= lastWinMsgSize.z / 2;
            pos.y -= lastWinMsgSize.w / 2;
            UI::SetCursorPos(pos + vec2(2,2));
            UI::SetNextItemWidth(side / 2.);
            UI::TextWrapped("\\$000" + winMsg);
            UI::SetCursorPos(pos);
            UI::SetNextItemWidth(side / 2.);
            UI::TextWrapped("\\$fff" + winMsg);
            lastWinMsgSize = UI::GetItemRect();
            UI::PopFont();
        }
    }

    bool get_IsMyTurn() {
        return IAmPlayer == ActivePlayer || IsSinglePlayerGame;
    }

    bool SquarePartOfWin(int2 xy) {
        for (uint i = 0; i < WinningSquares.Length; i++) {
            auto s = WinningSquares[i];
            if (xy.x == s.x && xy.y == s.y) return true;
        }
        return false;
    }

    const string IconForPlayer(TTGSquareState player) {
        if (player == TTGSquareState::Unclaimed) return Icons::QuestionCircleO;
        return player == TTGSquareState::Player1 ? Icons::CircleO : Icons::Kenney::Times;
        // return player == TTGSquareState::Player1 ? Icons::CircleO : Icons::Times;
    }

    void DrawTTGSquare(uint col, uint row, vec2 size) {
        auto sqState = GetSquareState(col, row);
        bool squareOpen = sqState == TTGSquareState::Unclaimed;
        string label = squareOpen ? "" : IconForPlayer(sqState);
        string id = "##sq-" + col + "," + row;

        bool isWinning = IsGameFinished && SquarePartOfWin(int2(col, row));
        bool isBeingChallenged = IsInClaimOrChallenge && challengeResult.col == col && challengeResult.row == row;
        bool ownedByMe = SquareOwnedByMe(col, row);
        bool ownedByThem = SquareOwnedByThem(col, row);

        UI::PushFont(boardFont);
        bool isDisabled = !IsWaitingForMove || not IsMyTurn || waitingForOwnMove;
        bool clicked = _SquareButton(label + id, size, col, row, isBeingChallenged, ownedByMe, ownedByThem, isWinning, isDisabled);
        UI::PopFont();

        if (clicked && !ownedByMe) {
            if (squareOpen) {
                TakeSquare(col, row);
            } else {
                ChallengeFor(col, row);
            }
        }
    }

    vec4 btnChallengeCol = vec4(.8, .4, 0, 1);
    vec4 btnWinningCol = vec4(.8, .4, 0, 1);

    bool _SquareButton(const string &in id, vec2 size, int col, int row, bool isBeingChallenged, bool  ownedByMe, bool ownedByThem, bool isWinning, bool isDisabled) {
        bool mapKnown = SquareKnown(col, row);

        if (isBeingChallenged) UI::PushStyleColor(UI::Col::Button, btnChallengeCol);
        else if (isWinning) UI::PushStyleColor(UI::Col::Button, btnWinningCol);
        else if (isDisabled) UI::PushStyleColor(UI::Col::Button, vec4(.2, .4, .7, .4));

        auto btnPos = UI::GetCursorPos();
        UI::BeginDisabled(isDisabled);
        bool clicked = UI::Button(id, size);
        UI::EndDisabled();
        UI::SetCursorPos(btnPos);
        clicked = (UI::InvisibleButton(id + "test", size) || clicked) && !isDisabled;
        bool isHovered = UI::IsItemHovered(UI::HoveredFlags::AllowWhenDisabled | UI::HoveredFlags::RectOnly);
        // bool isHovered = IsWithin(UI::GetMousePos(), btnPos, size);
        // print(tostring(UI::GetMousePos()) + tostring(btnPos) + tostring(size));

        if (isBeingChallenged || isWinning || isDisabled) UI::PopStyleColor(1);

        if (isHovered) {
            UI::BeginTooltip();
            UI::PushFont(hoverUiFont);

            if (ownedByMe) {
                // button disabled so never hovers
                UI::Text("Claimed by You");
            } else if (ownedByThem) {
                UI::Text("Challenge " + OpponentsName);
            } else if (mapKnown) {
                UI::Text("Win to claim!");
            }

            if (ownedByMe || ownedByThem || mapKnown) {
                UI::Separator();
                auto map = GetMap(col, row);
                int tid = map['TrackID'];
                UI::Text(ColoredString(map['Name']));
                UI::Text(map['LengthName']);
                UI::Text(map['DifficultyName']);
                DrawThumbnail(tostring(tid), 256);
            } else {
                UI::Text("Mystery Map.\nWin a race to claim!\n(Stays unclaimed otherwise.)");
            }

            UI::PopFont();
            UI::EndTooltip();
        }
        return clicked;
    }

    void TakeSquare(uint col, uint row) {
        if (GetSquareState(col, row) != TTGSquareState::Unclaimed) {
            warn("tried to take an occupied square");
            return;
        }
        waitingForOwnMove = true;
        client.SendPayload("G_TAKE_SQUARE", JsonObject2("col", col, "row", row));
    }

    void ChallengeFor(uint col, uint row) {
        auto sqState = GetSquareState(col, row);
        if (sqState == TTGSquareState::Unclaimed) {
            warn("tried to ChallengeFor an unclaimed square");
            return;
        }
        if (sqState == IAmPlayer) {
            return; // clicked own square
        }
        waitingForOwnMove = true;
        client.SendPayload("G_CHALLENGE_SQUARE", JsonObject2("col", col, "row", row));
        // get the corresponding map and load it
    }

    void DrawChatHidden() {
        if (DrawSubHeading1Button("Chat Hidden", "Show##" + idNonce)) {
            S_TTG_HideChat = false;
        }
    }

    string m_chatMsg;
    void DrawChat(bool drawHeading = true) {
        if (S_TTG_HideChat) {
            DrawChatHidden();
            return;
        }
        if (drawHeading) {
            if (DrawSubHeading1Button("Chat", "Hide##" + idNonce)) {
                S_TTG_HideChat = true;
                trace('hide chat');
            }
        }
        UI::PushFont(hoverUiFont);
        // UI::Text("Chat");
        // UI::Separator();
        bool changed;
        m_chatMsg = UI::InputText("##ttg-chat-msg"+idNonce, m_chatMsg, changed, UI::InputTextFlags::EnterReturnsTrue);
        if (changed) UI::SetKeyboardFocusHere(-1);
        UI::SameLine();
        if (UI::Button("Send") || changed) {
            startnew(CoroutineFunc(SendChatMsg));
        }
        UI::Separator();
        if (UI::BeginChild("##ttg-chat", vec2(), true, UI::WindowFlags::AlwaysAutoResize)) {
            // UI::Text("Chat Ix: " + client.chatNextIx);
            auto @chat = client.mainChat;
            string chatMsg;
            for (int i = 0; i < client.mainChat.Length; i++) {
                auto thisIx = (int(client.chatNextIx) - i - 1 + chat.Length) % chat.Length;
                auto msg = chat[thisIx];
                if (msg is null) break;
                // UI::Text("" + thisIx + ".");
                // UI::SameLine();
                chatMsg = ColoredString(string(msg['payload']['content']));
                UI::TextWrapped(Time::FormatString("%H:%M", int64(msg['ts'])) + " [ " + HighlightGray(string(msg['from']['username'])) + " ]:\n  " + chatMsg);
                UI::Dummy(vec2(0, 2));
            }
        }
        UI::EndChild();
        UI::PopFont();
    }

    void SendChatMsg() {
        client.SendChat(m_chatMsg, CGF::Visibility::global);
        m_chatMsg = "";
    }


    // string msgType;
    bool gotOwnMessage = false;
    TTGSquareState lastFrom = TTGSquareState::Unclaimed;
    int lastSeq = -1;

    bool MessageHandler(Json::Value@ msg) override {
        incomingEvents.InsertLast(msg);
        return true;
    }


    void AdvancePlayerTurns() {
        // todo: check for win
        if (CheckGameWon()) return;
        // else, update active player
        // ActivePlayer = ActivePlayer == IAmPlayer ? TheyArePlayer : IAmPlayer;
        ActivePlayer = InactivePlayer;
        turnCounter++;
    }

    // check if 3 squares are claimed and equal
    bool AreSquaresEqual(int2 a, int2 b, int2 c) {
        auto _a = GetSquareState(a.x, a.y);
        auto _b = GetSquareState(b.x, b.y);
        bool win = _a != TTGSquareState::Unclaimed
            && _a == _b
            && _b == GetSquareState(c.x, c.y);
        if (win) WinningPlayer = _a;
        WinningSquares.Resize(0);
        WinningSquares.InsertLast(a);
        WinningSquares.InsertLast(b);
        WinningSquares.InsertLast(c);
        return win;
    }

    bool CheckGameWon() {
        // check diags, rows, cols
        auto tmp = array<TTGSquareState>(3);
        bool gameWon = false
            // diags
            || AreSquaresEqual(int2(0, 0), int2(1, 1), int2(2, 2))
            || AreSquaresEqual(int2(0, 2), int2(1, 1), int2(2, 0))
            // columns
            || AreSquaresEqual(int2(0, 0), int2(0, 1), int2(0, 2))
            || AreSquaresEqual(int2(1, 0), int2(1, 1), int2(1, 2))
            || AreSquaresEqual(int2(2, 0), int2(2, 1), int2(2, 2))
            // rows
            || AreSquaresEqual(int2(0, 0), int2(1, 0), int2(2, 0))
            || AreSquaresEqual(int2(0, 1), int2(1, 1), int2(2, 1))
            || AreSquaresEqual(int2(0, 2), int2(1, 2), int2(2, 2))
            ;
        if (gameWon) {
            state = TTGGameState::GameFinished;
        }
        return gameWon;
    }

    bool get_IsPreStart() const {
        return state == TTGGameState::PreStart;
    }

    bool get_IsWaitingForMove() const {
        return state == TTGGameState::WaitingForMove;
    }

    bool get_IsInClaim() const {
        return state == TTGGameState::InClaim;
    }

    bool get_IsInChallenge() const {
        return state == TTGGameState::InChallenge;
    }

    bool get_IsInClaimOrChallenge() const {
        return IsInChallenge || IsInClaim;
    }

    bool get_IsInAGame() const {
        return !(IsGameFinished || IsPreStart);
    }

    bool get_IsGameFinished() const {
        return state == TTGGameState::GameFinished;
    }

    bool waitingForOwnMove = false;

    void GameLoop() {
        while (IsPreStart) yield();
        // while (ActivePlayer == TTGSquareState::Unclaimed) yield();
        // state = TTGGameState::WaitingForMove;
        while (not IsGameFinished && client.IsConnected) {
            yield();
            ProcessAvailableMsgs();
        }
    }

    void ProcessAvailableMsgs() {
        if (incomingEvents.Length > 0) {
            for (uint i = 0; i < incomingEvents.Length; i++) {
                auto msg = incomingEvents[i];
                // auto pl = msg['payload'];
                auto fromUser = msg['from'];
                // int seq = msg['seq'];
                gotOwnMessage = client.clientUid == string(fromUser['uid']);
                if (gotOwnMessage) waitingForOwnMove = false;
                auto fromPlayer = gotOwnMessage ? IAmPlayer : TheyArePlayer;
                lastFrom = fromPlayer;
                ProcessMove(msg);
            }
            incomingEvents.RemoveRange(0, incomingEvents.Length);
        }
    }


    bool IsValidMove(const string &in msgType, uint col, uint row, TTGSquareState fromPlayer) const {
        if (fromPlayer == TTGSquareState::Unclaimed) return false;
        if (IsGameFinished) return false;
        if (IsInChallenge || IsInClaim) {
            bool moveIsChallengeRes = msgType == "G_CHALLENGE_RESULT";
            if (!moveIsChallengeRes) return false;
            if (challengeResult.HasResultFor(fromPlayer)) return false;
            return true;
        } else if (IsWaitingForMove) {
            if (col >= 3 || row >= 3) return false;
            if (fromPlayer != ActivePlayer && !IsSinglePlayerGame) return false;
            bool moveIsClaiming = msgType == "G_TAKE_SQUARE";
            bool moveIsChallenging = msgType == "G_CHALLENGE_SQUARE";
            if (!moveIsChallenging && !moveIsClaiming) return false;
            if (moveIsChallenging) {
                auto sqState = GetSquareState(col, row);
                if (sqState == TTGSquareState::Unclaimed) return false;
                return sqState != fromPlayer || IsSinglePlayerGame;
            } else if (moveIsClaiming) {
                print('test move claiming');
                return GetSquareState(col, row) == TTGSquareState::Unclaimed;
            }
            return false;
        }
        return false;
    }


    void ProcessMove(Json::Value@ msg) {
        string msgType = msg['type'];
        auto pl = msg['payload'];
        int seq = pl['seq'];
        // deserialize move
        uint col, row;
        try {
            col = pl['col'];
            row = pl['row'];
        } catch {
            warn("Exception processing move: " + getExceptionInfo());
            return;
        }
        // check if valid move
        if (!IsValidMove(msgType, col, row, lastFrom)) {
            warn("Invalid move from " + tostring(lastFrom) + ": " + Json::Write(JsonObject2("type", msgType, "payload", pl)));
            return;
        }

        trace("Processing valid move of type: " + msgType + "; " + Json::Write(pl));

        // proceed with state mutation

        if (IsInChallenge || IsInClaim) {
            bool moveIsChallengeRes = msgType == "G_CHALLENGE_RESULT";
            if (!moveIsChallengeRes) throw("!moveIsChallengeRes: should be impossible");
            if (!challengeResult.active) throw("challenge is not active");
            if (!IsSinglePlayerGame) {
                challengeResult.SetPlayersTime(lastFrom, int(pl['time']));
            } else {
                // if we're in a single player game, set a slightly worse time for the inactive (we're always player 1)
                challengeResult.SetPlayersTime(ActivePlayer, int(pl['time']));
                challengeResult.SetPlayersTime(InactivePlayer, int(pl['time']) + 100);
            }
            if (challengeResult.IsResolved) {
                bool challengerWon = challengeResult.Winner != challengeResult.challenger;
                auto eType = TTGGameEventType((IsInChallenge ? 4 : 2) | (challengerWon ? 0 : 1));
                gameLog.InsertLast(TTGGameEvent_MapResult(this, eType, challengeResult, turnCounter + 1));

                challengeEndedAt = Time::Now;
                challengeResult.Reset();

                bool claimFailed = IsInClaim && challengerWon;
                auto sqState = claimFailed ? TTGSquareState::Unclaimed : challengeResult.Winner;
                SetSquareState(challengeResult.col, challengeResult.row, sqState);
                state = TTGGameState::WaitingForMove;
                AdvancePlayerTurns();
            }
        } else if (IsWaitingForMove) {
            if (col >= 3 || row >= 3) throw("impossible: col >= 3 || row >= 3");
            if (lastFrom != ActivePlayer && !IsSinglePlayerGame) throw("impossible: lastFrom != ActivePlayer");
            bool moveIsClaiming = msgType == "G_TAKE_SQUARE";
            bool moveIsChallenging = msgType == "G_CHALLENGE_SQUARE";
            if (!moveIsChallenging && !moveIsClaiming) throw("impossible: not a valid move");
            auto sqState = GetSquareState(col, row);
            if (moveIsChallenging) {
                if (sqState == TTGSquareState::Unclaimed) throw('invalid, square claimed');
                if (sqState == ActivePlayer) throw('invalid, cant challenge self');
                // begin challenge
                state = TTGGameState::InChallenge;
                challengeResult.Activate(col, row, ActivePlayer, state);
                startnew(CoroutineFunc(BeginChallengeSoon));
            } else if (moveIsClaiming) {
                if (sqState != TTGSquareState::Unclaimed) throw("claiming claimed square");
                state = TTGGameState::InClaim;
                challengeResult.Activate(col, row, ActivePlayer, state);
                startnew(CoroutineFunc(BeginChallengeSoon));
                // SetSquareState(col, row, ActivePlayer);
                // AdvancePlayerTurns();
            }
            MarkSquareKnown(col, row);
        }

        // todo: check if we
    }

    Json::Value@ currMap;
    int currTrackId;
    string currTrackIdStr;

    void BeginChallengeSoon() {
        auto col = challengeResult.col;
        auto row = challengeResult.row;
        auto map = GetMap(col, row);
        @currMap = map;
        currTrackId = map['TrackID'];
        currTrackIdStr = tostring(currTrackId);
        challengeResult.startTime = Time::Now + 3000;
        // sleep(3000);
    }

    Json::Value@ GetMap(int col, int row) {
        int mapIx = row * 3 + col;
        if (mapIx >= client.mapsList.Length) throw('bad map index');
        return client.mapsList[mapIx];
    }

    // void LoadMapNow(const string &in url) {
    //     auto app = cast<CGameManiaPlanet>(GetApp());
    //     app.BackToMainMenu();
    //     while (!app.ManiaTitleControlScriptAPI.IsReady) yield();
    //     app.ManiaTitleControlScriptAPI.PlayMap(MapUrl(currMap), "", "");
    // }

    vec4 challengeWindowBgCol = btnChallengeCol * vec4(.3, .3, .3, 1);
    uint challengeEndedAt;

    void DrawChallengeWindow() {
        if (!(IsInChallenge || IsInClaim) && challengeEndedAt + 6000 < Time::Now) return;
        if (CurrentlyInMap) return;
        if (currMap is null) return;
        auto flags = UI::WindowFlags::NoTitleBar
            | UI::WindowFlags::AlwaysAutoResize;
        UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(20, 20));
        UI::PushStyleVar(UI::StyleVar::WindowRounding, 20);
        UI::PushStyleVar(UI::StyleVar::WindowPadding, vec2(20, 20));
        UI::PushStyleColor(UI::Col::WindowBg, challengeWindowBgCol);
        if (UI::Begin("ttg-challenge-window-" + idNonce, flags)) {
            UI::PushFont(mapUiFont);
            string challengeStr;
            bool iAmChallenging = challengeResult.challenger == IAmPlayer;
            if (challengeResult.IsClaim) {
                if (iAmChallenging) challengeStr = "Beat " + OpponentsName + " to claim this map!";
                else challengeStr = "Beat " + OpponentsName + " to deny their claim!";
            } else {
                if (iAmChallenging) challengeStr = "You are challenging " + OpponentsName;
                else challengeStr = OpponentsName + " challenges you!";
            }
            UI::TextWrapped(challengeStr);
            UI::Text("First to finish wins!");
            UI::Text("Restarting does not zero timer!");
            UI::Separator();
            UI::Text("Map: " + ColoredString(currMap['Name']));
            UI::Text(string(currMap['LengthName']) + " / " + string(currMap['DifficultyName']));
            UI::AlignTextToFramePadding();
            if (challengeResult.IsResolved) {
                UI::Text("-- RESULT --");
                UI::Text(MyName + ": " + FormatChallengeTime(challengeResult.GetResultFor(IAmPlayer)));
                UI::Text(OpponentsName + ": " + FormatChallengeTime(challengeResult.GetResultFor(TheyArePlayer)));
                UI::AlignTextToFramePadding();
                UI::Text("Winner: " + GetPlayersName(challengeResult.Winner));
            } else if (challengeResult.HasResultFor(IAmPlayer)) {
                UI::Text("Waiting for " + OpponentsName + " to set a time.");
                UI::Text(MyName + ": " + FormatChallengeTime(challengeResult.GetResultFor(IAmPlayer)));
            } else {
                if (challengeResult.startTime > Time::Now) {
                    auto timeLeft = float(challengeResult.startTime - Time::Now) / 1000.;
                    UI::Text("Starting in: " + Text::Format("%.1f", timeLeft));
                } else {
                    UI::BeginDisabled(disableLaunchMapBtn);
                    if (UI::Button("LAUNCH MAP")) {
                        disableLaunchMapBtn = true;
                        startnew(CoroutineFunc(RunChallengeAndReportResult));
                    }
                    UI::EndDisabled();
                }
            }
            UI::PopFont();
            UI::Separator();
            DrawThumbnail(currTrackIdStr);
        }
        UI::End();
        UI::PopStyleColor(1);
        UI::PopStyleVar(3);
    }

    const string FormatChallengeTime(int time) {
        if (time >= DNF_TEST) return "DNF";
        return Time::Format(time);
    }

    // relative to Time::Now to avoid pause menu strats
    int challengeStartTime = -1;
    int challengeEndTime = -1;
    int challengeScreenTimeout = -1;
    int currGameTime = -1;
    int currPeriod = 15;  // frame time
    bool challengeRunActive = false;
    bool disableLaunchMapBtn = false;

    void RunChallengeAndReportResult() {
        challengeStartTime = -1;
        currGameTime = -1;
        currPeriod = 15;
        // join map
        challengeRunActive = true;
        LoadMapNow(MapUrl(currMap));
        while (!CurrentlyInMap) yield();
        sleep(50);
        // wait for UI sequence to be playing
        while (GetApp().CurrentPlayground is null) yield();
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        while (cp.Players.Length < 1) yield();
        auto player = cast<CSmScriptPlayer>(cast<CSmPlayer>(cp.Players[0]).ScriptAPI);
        while (cp.UIConfigs.Length < 0) yield();
        auto uiConfig = cp.UIConfigs[0];
        while (uiConfig.UISequence != CGamePlaygroundUIConfig::EUISequence::Intro) yield();
        // re enable the launch map button here, is good enough and pretty close to the first time we can safely re-enable
        disableLaunchMapBtn = false;
        while (uiConfig.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        sleep(300); // we don't need to get the time immediately, so give some time for values to update
        while (player.StartTime < 0) yield();
        startnew(HideGameUI::OnMapLoad);
        // record start
        currGameTime = GetApp().PlaygroundScript.Now;
        challengeStartTime = Time::Now + (player.StartTime - currGameTime);
        log_info("Set challenge start time: " + challengeStartTime);
        // wait for finish timer
        int duration;
        while (uiConfig is null || uiConfig.UISequence != CGamePlaygroundUIConfig::EUISequence::Finish) {
            duration = Time::Now - challengeStartTime;
            auto oppTime = challengeResult.GetResultFor(TheyArePlayer, DNF_TIME);
            auto timeLeft = oppTime + AUTO_DNF_TIMEOUT - duration;
            // if (timeLeft < 0) {
            //     cast<CGameManiaPlanet>(GetApp()).BackToMainMenu();
            // }
            // timeLeft < 0 ||
            if (GetApp().PlaygroundScript is null || uiConfig is null) {
                // player quit (unless auto DNF)
                ReportChallengeResult(DNF_TIME); // more than 24 hrs, just
                warn("Player quit map");
                EndChallenge();
                return;
            }
            currGameTime = GetApp().PlaygroundScript.Now;
            challengeEndTime = Time::Now;
            currPeriod = GetApp().PlaygroundScript.Period;
            yield();
        }
        // we over measure if we set the end time here, and under measure if we use what was set earlier.
        // so use last time plus the period. add to end time so GUI updates
        challengeEndTime += currPeriod;
        duration = challengeEndTime - challengeStartTime;
        // report result
        ReportChallengeResult(duration);
        sleep(3000);
        EndChallenge();
    }

    void DrawThumbnail(const string &in trackId, float sideLen = 0.) {
        if (!client.MapDoesNotHaveThumbnail(trackId)) {
            auto @tex = client.GetCachedMapThumb(trackId);
            if (tex is null) {
                UI::Text("Loading thumbnail..");
            } else {
                if (sideLen <= 0)
                    UI::Image(tex.ui);
                else
                    UI::Image(tex.ui, vec2(sideLen, sideLen));
            }
        } else {
            UI::Text("(No Thumbnail)");
        }
    }

    void EndChallenge() {
        challengeRunActive = false;
        ReturnToMenu();
    }

    void ReportChallengeResult(int duration) {
        auto pl = JsonObject1("time", duration);
        pl['col'] = challengeResult.col;
        pl['row'] = challengeResult.row;
        client.SendPayload("G_CHALLENGE_RESULT", pl);
    }

    void LogPlayerStartTime() {
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        if (cp is null) return;
        if (cp.Players.Length == 0) return;
        auto p = cast<CSmPlayer>(cp.Players[0]);
        if (p is null) return;
        auto player = cast<CSmScriptPlayer>(p.ScriptAPI);
        if (player is null) return;
        if (GetApp().PlaygroundScript is null) return;
        auto gt = GetApp().PlaygroundScript.Now;
        print("Spawned: " + tostring(player.SpawnStatus) + ", GameTime: " + gt + ", StartTime: " + player.StartTime);
    }
}


class ChallengeInfo {
    uint col;
    uint row;
    uint seq;
}


class ChallengeResultState {
    int player1Time = -1;
    int player2Time = -1;
    bool active = false;
    int row = -1;
    int col = -1;
    int startTime = -1;
    TTGSquareState challenger = TTGSquareState::Unclaimed;
    TTGSquareState defender = TTGSquareState::Unclaimed;
    TTGGameState challengeType;

    void Reset() {
        startTime = -1;
        active = false;
    }

    void Activate(uint col, uint row, TTGSquareState challenger, TTGGameState type) {
        if (active) throw("already active");
        this.col = int(col);
        this.row = int(row);
        active = true;
        player1Time = -1;
        player2Time = -1;
        this.challenger = challenger;
        this.defender = challenger == TTGSquareState::Player1 ? TTGSquareState::Player2 : TTGSquareState::Player1;
        challengeType = type;
    }

    bool get_IsClaim() const {
        return challengeType == TTGGameState::InClaim;
    }

    bool get_IsChallenge() const {
        return challengeType == TTGGameState::InChallenge;
    }

    bool get_IsResolved() const {
        return player1Time > 0 && player2Time > 0;
    }

    TTGSquareState get_Winner() const {
        if (!IsResolved) return TTGSquareState::Unclaimed;
        if (BothPlayersDNFed) return defender;
        if (player1Time == player2Time) return defender;
        if (player1Time < player2Time) return TTGSquareState::Player1;
        return TTGSquareState::Player2;
    }

    bool get_BothPlayersDNFed() const {
        return player1Time >= DNF_TEST && player2Time >= DNF_TEST;
    }

    bool get_HavePlayer1Res() const {
        return player1Time > 0;
    }

    bool get_HavePlayer2Res() const {
        return player2Time > 0;
    }

    void SetPlayersTime(TTGSquareState player, int time) {
        if (player == TTGSquareState::Player1) {
            player1Time = time;
        } else if (player == TTGSquareState::Player2) {
            player2Time = time;
        } else {
            throw("unknown player");
        }

        if (IsResolved) {
            active = false;
        }
    }

    bool HasResultFor(TTGSquareState player) const {
        if (player == TTGSquareState::Unclaimed) throw("should never pass unclaimed, here");
        return (player == TTGSquareState::Player1 && HavePlayer1Res) || (player == TTGSquareState::Player2 && HavePlayer2Res);
    }

    int GetResultFor(TTGSquareState player, int _default = -1) const {
        if (player == TTGSquareState::Unclaimed) throw("should never pass unclaimed, here");
        auto ret = player == TTGSquareState::Player1 ? player1Time : player2Time;
        if (ret < 0) return _default;
        return ret;
    }

    int get_ChallengerTime() const {
        return GetResultFor(challenger);
    }

    int get_DefenderTime() const {
        return GetResultFor(defender);
    }
}

enum TTGGameEventType {
    ClaimFail = 2,
    ClaimWin = 3,
    ChallengeWin = 4,
    ChallengeFail = 5,
}

interface TTGGameEvent {
    void Draw();
}


class TTGGameEvent_StartingPlayer : TTGGameEvent {
    string msg;
    TTGGameEvent_StartingPlayer(TTGSquareState player, const string &in name) {
        msg = "0. Player " + (int(player) + 1) + " (" + name + ") starts.";
    }

    void Draw() {
        UI::TextWrapped(msg);
    }
}

class TTGGameEvent_PlayerEvent : TTGGameEvent {
    string msg;
    TTGGameEvent_PlayerEvent(const string &in type, Json::Value@ pl) {
        msg = string(pl['username']) + (type == "PLAYER_JOINED" ? " Joined." : " Left.");
    }

    void Draw() {
        UI::TextWrapped(msg);
    }
}

class TTGGameEvent_MapResult : TTGGameEvent {
    TicTacGo@ ttg;
    TTGGameEventType Type;
    TTGSquareState Challenger;
    TTGSquareState Defender;
    int2 xy;
    int challengerTime;
    int defenderTime;
    string mapName;
    Json::Value@ map;
    int trackId;
    int moveNumber;
    protected string msg;

    TTGGameEvent_MapResult(TicTacGo@ ttg, TTGGameEventType type, ChallengeResultState@ cr, int moveNumber) {
        @this.ttg = ttg;
        Type = type;
        Challenger = cr.challenger;
        Defender = cr.defender;
        xy = int2(cr.col, cr.row);
        this.challengerTime = cr.ChallengerTime;
        this.defenderTime = cr.DefenderTime;
        @map = ttg.GetMap(xy.x, xy.y);
        this.mapName = ColoredString(map['Name']);
        this.trackId = map['TrackID'];
        // this.mapName = ttg.GetMap(xy.x, xy.y)['Name'];
        this.moveNumber = moveNumber;
        string cName = ttg.GetPlayersName(Challenger);
        string dName = ttg.GetPlayersName(Defender);
        msg = tostring(this.moveNumber) + ". ";
        msg += cName;
        bool isChallenge = 4 & type > 0;
        // bool isClaim = !isChallenge;
        bool isWin = 1 & type == 1;
        if (!isChallenge) {
            msg += isWin ? HighlightWin(" claimed ") : (HighlightLoss(" failed to claim "));
            msg += SquareCoordStr;
        } else {
            msg += Highlight(" challenged ") + dName + " to ";
            msg += SquareCoordStr;
            msg += isWin ? " and " + HighlightWin("won") : (" but " + HighlightLoss("lost"));
        }
        msg += ".\n";
        bool cWon = challengerTime < defenderTime;
        string cTime = challengerTime < DNF_TEST ? HighlightWL(cWon, Time::Format(challengerTime)) : HighlightLoss("DNF");
        string dTime = defenderTime < DNF_TEST ? HighlightWL(!cWon, Time::Format(defenderTime)) : HighlightLoss("DNF");
        bool showDelta = challengerTime + defenderTime < DNF_TEST;
        msg += "  " + cName + ": " + cTime + "\n";
        msg += "  " + dName + ": " + dTime;
        if (showDelta)
            msg += "\n  Delta: " + Time::Format(Math::Abs(challengerTime - defenderTime));
    }

    const string get_SquareCoordStr() const {
        return Highlight("(" + (xy.x + 1) + ", " + (xy.y + 1) + ")");
    }

    void Draw() {
        UI::TextWrapped(this.msg);
    }
}


string HighlightGray(const string &in msg) {
    return "\\$<\\$999" + msg + "\\$>";
}

string Highlight(const string &in msg) {
    return "\\$<\\$5ae" + msg + "\\$>";
}

string HighlightWL(bool win, const string &in msg) {
    return win ? HighlightWin(msg) : HighlightLoss(msg);
}

string HighlightWin(const string &in msg) {
    return "\\$<\\$7e1" + msg + "\\$>";
}

string HighlightLoss(const string &in msg) {
    return "\\$<\\$e71" + msg + "\\$>";
}


namespace HideGameUI {
    string[] HidePages =
        { "UIModule_Race_Chrono"
        , "UIModule_Race_RespawnHelper"
        // , "UIModule_Race_Checkpoint"
        , "UIModule_Race_Record"
        };
    void OnMapLoad() {
        auto app = cast<CGameManiaPlanet>(GetApp());
        while (app.Network.ClientManiaAppPlayground is null) yield();
        // wait for UI layers and a few frames extra
        auto uiConf = app.Network.ClientManiaAppPlayground;
        while (uiConf.UILayers.Length < 10) yield();
        for (uint i = 0; i < uiConf.UILayers.Length; i++) {
            auto layer = uiConf.UILayers[i];
            string first100Chars = string(layer.ManialinkPage.SubStr(0, 100));
            auto parts = first100Chars.Trim().Split('manialink name="');
            if (parts.Length < 2) continue;
            auto pageName = parts[1].Split('"')[0];
            if (pageName.StartsWith("UIModule_Race") && HidePages.Find(pageName) >= 0) {
                layer.IsVisible = false;
            }
        }
    }
}
