enum TTGSquareState {
    Unclaimed = -1,
    Player1 = 0,
    Player2 = 1
}

UI::Font@ boardFont = UI::LoadFont("DroidSans.ttf", 40., -1, -1, true, true, true);
int defaultNvgFont = nvg::LoadFont("DroidSans.ttf", true, true);

enum TTGGameState {
    // proceeds to waiting for move
    PreStart
    // can proceed to claim (immediate) or challenge (proceed to InChallenge)
    , WaitingForMove
    // , SetSquareState
    // , AdvanceTurn
    // , CheckForWin
    // , SetNextPlayer
    , InChallenge
    , GameFinished
}



class TicTacGo : Game::Engine {
    Game::Client@ client;
    TTGSquareState[][] boardState;

    TTGGameState state = TTGGameState::PreStart;

    TTGSquareState IAmPlayer;
    TTGSquareState TheyArePlayer;
    TTGSquareState ActivePlayer;
    TTGSquareState WinningPlayer;

    ChallengeResultState@ challengeResult;

    Json::Value@[] incomingEvents;

    TicTacGo(Game::Client@ client) {
        @this.client = client;
        @challengeResult = ChallengeResultState();
    }

    void ResetState() {
        trace("TTG State Reset!");
        // reset board
        boardState.Resize(3);
        for (uint x = 0; x < boardState.Length; x++) {
            boardState[x].Resize(3);
            for (uint y = 0; y < boardState[x].Length; y++) {
                boardState[x][y] = TTGSquareState::Unclaimed;
            }
        }
        boardState.Resize(3);
        state = TTGGameState::PreStart;
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

    vec2 get_framePadding() {
        return UI::GetStyleVarVec2(UI::StyleVar::FramePadding);
    };

    GameInfoFull@ get_GameInfo() {
        return client.gameInfoFull;
    }

    const string get_ActivePlayersName() {
        string uid;
        if (ActivePlayer == TTGSquareState::Unclaimed) {
            return "";
        }
        if (ActivePlayer == IAmPlayer) {
            uid = client.clientUid;
        } else {
            uid = GameInfo.teams[int(ActivePlayer)][0];
        }
        return client.GetPlayerName(uid);
    }

    const string get_OpponentsName() {
        string uid = (GameInfo.teams[0][0] == client.clientUid)
            ? GameInfo.teams[1][0]
            : GameInfo.teams[0][0];
        return client.GetPlayerName(uid);
    }

    void SetPlayers() {
        while (GameInfo is null) {
            warn("SetPlayers found null game info, yielding");
            yield();
        }
        ActivePlayer = GameInfo.team_order[0] == 1
            ? TTGSquareState::Player2
            : TTGSquareState::Player1;
        if (GameInfo.teams[0][0] == client.clientUid) {
            IAmPlayer = TTGSquareState::Player1;
            TheyArePlayer = TTGSquareState::Player2;
        } else {
            IAmPlayer = TTGSquareState::Player2;
            TheyArePlayer = TTGSquareState::Player1;
        }
        print("ActivePlayer (start): " + tostring(ActivePlayer));
    }

    void OnGameStart() {
        trace("On game start!");
        ResetState();
        SetPlayers();
        startnew(CoroutineFunc(GameLoop));
    }

    void OnGameEnd() {
        // gameFinished = true;
        state = TTGGameState::GameFinished;
    }

    TTGSquareState GetSquareState(int col, int row) const {
        return boardState[col][row];
    }

    void SetSquareState(int col, int row, TTGSquareState newState) {
        trace("set (" + col + ", " + row + ") to " + tostring(newState));
        boardState[col][row] = newState;
        PrettyPrintBoardState();
    }

    bool SquareOwnedByMe(int col, int row) const {
        return IAmPlayer == boardState[col][row];
    }

    void Render() {
        if (!CurrentlyInMap) return;
        // print("render? " + challengeStartTime + ", gt: " + currGameTime);
        if (challengeStartTime < 0) return;
        if (currGameTime < 0) return;
        // print("render going ahead");
        auto duration = currGameTime - challengeStartTime;
        string sign = duration < 0 ? "-" : "";
        duration = Math::Abs(duration);
        nvg::Reset();
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Top);
        nvg::FontFace(defaultNvgFont);
        nvg::FontSize(150);
        auto textPos = S_TimerPosition;
        nvg::FillColor(vec4(0, 0, 0, 1));
        nvg::Text(textPos + vec2(13, 13), sign + Time::Format(duration));
        nvg::FillColor(vec4(1, 1, 1, 1));
        nvg::Text(textPos, sign + Time::Format(duration));
    }

    void RenderInterface() {
        // LogPlayerStartTime();
        // Tic Tac Toe interface
        auto available = UI::GetContentRegionAvail();
        auto lrColSize = available * vec2(.25, 1);
        auto midColSize = available * vec2(.5, 1);
        // player 1
        DrawLeftCol(lrColSize);
        UI::SameLine();
        // game board
        DrawMiddleCol(midColSize);
        UI::SameLine();
        // player 2
        DrawRightCol(lrColSize);
        DrawChallengeWindow();
    }

    // player 1 col
    void DrawLeftCol(vec2 size) {
        if (UI::BeginChild("ttg-p1", size, true)) {
            DrawPlayer(0);
        }
        UI::EndChild();
    }

    // player 2 col
    void DrawRightCol(vec2 size) {
        if (UI::BeginChild("ttg-p2", size, true)) {
            DrawPlayer(1);
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

    void DrawPlayer(int team) {
        auto playerNum = team + 1;
        UI::Text("Player: " + playerNum);
        UI::Text(client.GetPlayerName(GameInfo.teams[team][0]));
        UI::Text("Team Order: " + GameInfo.team_order[0] + ", " + GameInfo.team_order[1]);
        if (IsGameFinished) {
            UI::Dummy(vec2(0, 100));
            if (UI::Button("Leave##game")) {
                // once for game, once for room
                client.SendLeave();
                client.SendLeave();
            }
        }
    }

    void DrawTicTacGoBoard(vec2 size) {
        size.y -= UI::GetFrameHeightWithSpacing();
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
            UI::Text(ActivePlayersName + "'s Turn");
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
            UI::PushFont(boardFont);
            UI::SetNextItemWidth(side / 2.);
            UI::SetCursorPos(boardTL + (size * .25));
            UI::TextWrapped("Winner: " + ActivePlayersName);
            UI::PopFont();
        }
    }

    bool get_IsMyTurn() {
        return IAmPlayer == ActivePlayer;
    }

    void DrawTTGSquare(uint col, uint row, vec2 size) {
        auto sqState = GetSquareState(col, row);
        bool squareOpen = sqState == TTGSquareState::Unclaimed;
        string label = squareOpen ? ""
            : (sqState == TTGSquareState::Player1 ? Icons::CircleO : Icons::Times);
        string id = "##sq-" + col + "," + row;

        bool isBeingChallenged = IsInChallenge && challengeResult.col == col && challengeResult.row == row;

        UI::PushFont(boardFont);
        UI::BeginDisabled(IsInChallenge || IsGameFinished || not IsMyTurn || waitingForOwnMove || SquareOwnedByMe(col, row));
        bool clicked = _SquareButton(label + id, size, isBeingChallenged);
        UI::EndDisabled();
        UI::PopFont();

        if (clicked) {
            if (squareOpen) {
                TakeSquare(col, row);
            } else {
                ChallengeFor(col, row);
            }
        }
    }

    vec4 btnChallengeCol = vec4(.8, .4, 0, 1);

    bool _SquareButton(const string &in id, vec2 size, bool isBeingChallenged) {
        if (isBeingChallenged) {
            UI::PushStyleColor(UI::Col::Button, btnChallengeCol);
        }
        bool clicked = UI::Button(id, size);
        if (isBeingChallenged) UI::PopStyleColor(1);
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
        ActivePlayer = ActivePlayer == IAmPlayer ? TheyArePlayer : IAmPlayer;
    }

    // check if 3 squares are claimed and equal
    bool AreSquaresEqual(int2 a, int2 b, int2 c) {
        auto _a = GetSquareState(a.x, a.y);
        auto _b = GetSquareState(b.x, b.y);
        bool win = _a != TTGSquareState::Unclaimed
            && _a == _b
            && _b == GetSquareState(c.x, c.y);
        if (win) WinningPlayer = _a;
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

    bool get_IsInChallenge() const {
        return state == TTGGameState::InChallenge;
    }

    bool get_IsGameFinished() const {
        return state == TTGGameState::GameFinished;
    }

    bool waitingForOwnMove = false;

    void GameLoop() {
        state = TTGGameState::WaitingForMove;
        while (not IsGameFinished) {
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
        if (IsInChallenge) {
            bool moveIsChallengeRes = msgType == "G_CHALLENGE_RESULT";
            if (!moveIsChallengeRes) return false;
            if (challengeResult.HasResultFor(fromPlayer)) return false;
            return true;
        } else if (IsWaitingForMove) {
            if (col >= 3 || row >= 3) return false;
            if (fromPlayer != ActivePlayer) return false;
            bool moveIsClaiming = msgType == "G_TAKE_SQUARE";
            bool moveIsChallenging = msgType == "G_CHALLENGE_SQUARE";
            if (!moveIsChallenging && !moveIsClaiming) return false;
            if (moveIsChallenging) {
                auto sqState = GetSquareState(col, row);
                if (sqState == TTGSquareState::Unclaimed) return false;
                return sqState != fromPlayer;
            } else if (moveIsClaiming) {
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

        if (IsInChallenge) {
            bool moveIsChallengeRes = msgType == "G_CHALLENGE_RESULT";
            if (!moveIsChallengeRes) throw("!moveIsChallengeRes: should be impossible");
            if (!challengeResult.active) throw("challenge is not active");
            challengeResult.SetPlayersTime(lastFrom, int(pl['time']));
            if (challengeResult.IsResolved) {
                challengeResult.Reset();
                SetSquareState(challengeResult.col, challengeResult.row, challengeResult.Winner);
                state = TTGGameState::WaitingForMove;
                AdvancePlayerTurns();
            }
        } else if (IsWaitingForMove) {
            if (col >= 3 || row >= 3) throw("impossible: col >= 3 || row >= 3");
            if (lastFrom != ActivePlayer) throw("impossible: lastFrom != ActivePlayer");
            bool moveIsClaiming = msgType == "G_TAKE_SQUARE";
            bool moveIsChallenging = msgType == "G_CHALLENGE_SQUARE";
            if (!moveIsChallenging && !moveIsClaiming) throw("impossible: not a valid move");
            if (moveIsChallenging) {
                auto sqState = GetSquareState(col, row);
                if (sqState == TTGSquareState::Unclaimed) throw('invalid, square claimed');
                if (sqState == ActivePlayer) throw('invalid, cant challenge self');
                // begin challenge
                challengeResult.Activate(col, row);
                state = TTGGameState::InChallenge;
                // if (seq >= client.GameReplayNbMsgs)
                startnew(CoroutineFunc(BeginChallengeSoon));
            } else if (moveIsClaiming) {
                if (GetSquareState(col, row) != TTGSquareState::Unclaimed) throw("claiming claimed square");
                SetSquareState(col, row, ActivePlayer);
                AdvancePlayerTurns();
            }
        }

        // todo: check if we
    }

    Json::Value@ currMap;
    int currTrackId;
    string currTrackIdStr;

    void BeginChallengeSoon() {
        auto col = challengeResult.col;
        auto row = challengeResult.row;
        int mapIx = row * 3 + col;
        if (mapIx >= client.mapsList.Length) throw('bad map index');
        auto map = client.mapsList[mapIx];
        @currMap = map;
        currTrackId = map['TrackID'];
        currTrackIdStr = tostring(currTrackId);
        challengeResult.startTime = Time::Now + 3000;
        sleep(3000);
    }

    // void LoadMapNow(const string &in url) {
    //     auto app = cast<CGameManiaPlanet>(GetApp());
    //     app.BackToMainMenu();
    //     while (!app.ManiaTitleControlScriptAPI.IsReady) yield();
    //     app.ManiaTitleControlScriptAPI.PlayMap(MapUrl(currMap), "", "");
    // }

    vec4 challengeWindowBgCol = btnChallengeCol * vec4(.3, .3, .3, 1);

    void DrawChallengeWindow() {
        if (!IsInChallenge || CurrentlyInMap) return;
        auto flags = UI::WindowFlags::NoTitleBar
            | UI::WindowFlags::AlwaysAutoResize;
        UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(20, 20));
        UI::PushStyleVar(UI::StyleVar::WindowRounding, 20);
        UI::PushStyleVar(UI::StyleVar::WindowPadding, vec2(20, 20));
        UI::PushStyleColor(UI::Col::WindowBg, challengeWindowBgCol);
        if (UI::Begin("ttg-challenge-window-" + client.clientUid, flags)) {
            UI::PushFont(boardFont);
            string challengeStr;
            if (IsMyTurn) {
                challengeStr = "You are challenging " + OpponentsName;
            } else {
                challengeStr = OpponentsName + " challenges you!";
            }
            UI::Text(challengeStr);
            UI::Text("First to finish wins!");
            UI::Text("Restarting does not zero timer!");
            UI::Separator();
            UI::Text("Map: " + ColoredString(currMap['Name']) + " (" + string(currMap['LengthName']) + ")");
            UI::AlignTextToFramePadding();
            if (challengeResult.startTime > Time::Now) {
                auto timeLeft = float(challengeResult.startTime - Time::Now) / 1000.;
                UI::Text("Starting in: " + Text::Format("%.1f", timeLeft));
            } else {
                if (UI::Button("LAUNCH MAP")) {
                    startnew(CoroutineFunc(RunChallengeAndReportResult));
                }
            }
            UI::PopFont();
            UI::Separator();
            if (!client.MapDoesNotHaveThumbnail(currTrackIdStr)) {
                auto @tex = client.GetCachedMapThumb(currTrackIdStr);
                if (tex is null) {
                    UI::Text("Loading thumbnail..");
                } else {
                    auto s = UI::GetWindowContentRegionWidth();
                    UI::Image(tex.ui);
                }
            }
        }
        UI::End();
        UI::PopStyleColor(1);
        UI::PopStyleVar(3);
    }

    int challengeStartTime = -1;
    int currGameTime = -1;

    void RunChallengeAndReportResult() {
        challengeStartTime = -1;
        currGameTime = -1;
        // join map
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
        while (uiConfig.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        sleep(300); // we don't need to get the time immediately, so give some time for values to update
        while (player.StartTime < 0) yield();
        // record start
        challengeStartTime = player.StartTime;
        log_info("Set challenge start time: " + challengeStartTime);
        // wait for finish timer
        while (uiConfig.UISequence != CGamePlaygroundUIConfig::EUISequence::Finish) {
            if (GetApp().PlaygroundScript is null) {
                // player quit
                client.SendPayload("G_CHALLENGE_RESULT", JsonObject1("time", 9999999));
                warn("Player quit game");
                ReturnToMenu();
                return;
            }
            currGameTime = GetApp().PlaygroundScript.Now;
            yield();
        }
        auto endTime = GetApp().PlaygroundScript.Now;
        auto duration = int(endTime) - challengeStartTime;
        // report result
        client.SendPayload("G_CHALLENGE_RESULT", JsonObject1("time", duration));
        sleep(2000);
        ReturnToMenu();
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

    bool get_CurrentlyInMap() {
        return GetApp().CurrentPlayground !is null;
    }
}


/** Render function called every frame intended only for menu items in the main menu of the `UI`.
*/
void RenderMenuMain() {
    if (UI::MenuItem("load map")) {
        LoadMapNow("https://cgf.s3.nl-1.wasabisys.com/72091.Map.Gbx");
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

    void Reset() {
        startTime = -1;
        player1Time = -1;
        player2Time = -1;
        active = false;
        col = -1;
        row = -1;
    }

    void Activate(uint col, uint row) {
        if (active) throw("already active");
        this.col = int(col);
        this.row = int(row);
        active = true;
    }

    bool get_IsResolved() const {
        return player1Time > 0 && player2Time > 0;
    }

    TTGSquareState get_Winner() const {
        if (!IsResolved) return TTGSquareState::Unclaimed;
        if (player1Time < player2Time) return TTGSquareState::Player1;
        return TTGSquareState::Player2;
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
        }

        if (IsResolved) {
            active = false;
        }
    }

    bool HasResultFor(TTGSquareState player) const {
        if (player == TTGSquareState::Unclaimed) throw("should never pass unclaimed, here");
        return (player == TTGSquareState::Player1 && HavePlayer1Res) || (player == TTGSquareState::Player2 && HavePlayer2Res);
    }
}
