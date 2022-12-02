enum TTGSquareState {
    Unclaimed = -1,
    Player1 = 0,
    Player2 = 1
}

UI::Font@ boardFont = UI::LoadFont("DroidSans.ttf", 40., -1, -1, true, true, true);

class TicTacGo : Game::Engine {
    Game::Client@ client;
    TTGSquareState[][] boardState;

    TTGSquareState IAmPlayer;
    TTGSquareState TheyArePlayer;
    TTGSquareState ActivePlayer;
    bool gameFinished = false;

    TicTacGo(Game::Client@ client) {
        @this.client = client;
    }

    void ResetState() {
        // reset board
        boardState.Resize(3);
        for (uint x = 0; x < boardState.Length; x++) {
            boardState[x].Resize(3);
            for (uint y = 0; y < boardState[x].Length; y++) {
                boardState[x][y] = TTGSquareState::Unclaimed;
            }
        }
        boardState.Resize(3);
        gameFinished = false;
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

    void SetPlayers() {
        ActivePlayer = TTGSquareState::Player1;
        while (GameInfo is null) yield();
        if (GameInfo.teams[0][0] == client.clientUid) {
            IAmPlayer = TTGSquareState::Player1;
            TheyArePlayer = TTGSquareState::Player2;
        } else {
            IAmPlayer = TTGSquareState::Player2;
            TheyArePlayer = TTGSquareState::Player1;
        }
    }

    void OnGameStart() {
        ResetState();
        SetPlayers();
        startnew(CoroutineFunc(GameLoop));
    }

    void OnGameEnd() {
        gameFinished = true;
    }

    TTGSquareState GetSquareState(int col, int row) {
        return boardState[col][row];
    }

    void RenderInterface() {
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
    }

    bool get_IsMyTurn() {
        return IAmPlayer == ActivePlayer;
    }

    void DrawTTGSquare(uint col, uint row, vec2 size) {
        auto sqState = GetSquareState(col, row);
        bool squareOpen = sqState == TTGSquareState::Unclaimed;
        string label = squareOpen ? "(unclaimed)"
            : (sqState == TTGSquareState::Player1 ? Icons::Times : Icons::CircleO);
        string id = "##sq-" + col + "," + row;

        UI::BeginDisabled(not IsMyTurn || waitingForOwnMove);
        bool clicked = UI::Button(label + id, size);
        UI::EndDisabled();

        if (clicked) {
            if (squareOpen) {
                TakeSquare(col, row);
            } else {
                ChallengeFor(col, row);
            }
        }
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
        if (sqState != TTGSquareState::Unclaimed) {
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

    string msgType;
    bool gotOwnMessage = false;
    TTGSquareState lastFrom = TTGSquareState::Unclaimed;
    bool MessageHandler(Json::Value@ msg) override {
        msgType = msg['type'];
        auto pl = msg['payload'];
        auto from = msg['from'];
        gotOwnMessage = client.clientUid == string(from['uid']);
        auto fromPlayer = gotOwnMessage ? IAmPlayer : TheyArePlayer;
        lastFrom = fromPlayer;
        ProcessMove(pl);
        return true;
    }

    bool ProcessMove(Json::Value@ pl) {
        // check if valid move
        // if so, mutate state
    }

    bool waitingForOwnMove = false;

    void GameLoop() {
        while (not gameFinished) {
            yield();
            while (waitingForOwnMove && lastFrom != IAmPlayer)
                yield();
            waitingForOwnMove = false;
        }
    }
}
