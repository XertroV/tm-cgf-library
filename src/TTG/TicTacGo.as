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
    // string idNonce;

    TicTacGoState@ stateObj;

    Json::Value@[] incomingEvents;

    TicTacGo(Game::Client@ client, bool setRandomNonce = false) {
        // if (setRandomNonce)
        //     idNonce = client.clientUid;
            // idNonce = tostring(Math::Rand(0, 99999999));
        @this.client = client;
        @this.stateObj = TicTacGoState(client);
        client.AddMessageHandler("PLAYER_LEFT", CGF::MessageHandler(MsgHandler_PlayerEvent));
        client.AddMessageHandler("PLAYER_JOINED", CGF::MessageHandler(MsgHandler_PlayerEvent));
        client.AddMessageHandler("LOBBY_LIST", CGF::MessageHandler(MsgHandler_Ignore));
        ResetState();
    }

    const string get_idNonce() {
        return client.clientUid;
    }

    void ResetState() {
        trace("TTG State Reset!");
        stateObj.Reset();
    }

    void PrettyPrintBoardState() {
        string b = "\n";
        for (uint row = 0; row < 3; row++) {
            b += "\n";
            for (uint col = 0; col < 3; col++) {
                auto s = stateObj.GetSquareState(col, row).owner;
                b += s == TTGSquareState::Unclaimed ? "-" : (s == TTGSquareState::Player1 ? "1" : "2");
            }
        }
        print(b);
    }

    bool MsgHandler_PlayerEvent(Json::Value@ j) {
        if (!client.IsInGame) return true;
        string type = j['type'];
        bool addToLog = type == "PLAYER_LEFT" || type == "PLAYER_JOINED";
        if (addToLog) stateObj.gameLog.InsertLast(TTGGameEvent_PlayerEvent(type, j['payload']));
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

    void OnGameStart() {
        trace("On game start!");
        MM::setMenuPage("/empty");
        ResetState();
        stateObj.OnGameStart();
        startnew(CoroutineFunc(GameLoop));
    }

    void OnGameEnd() {
        stateObj.OnGameEnd();
        MM::setMenuPage("/home");
    }

    void Render() {
        if (!CurrentlyInMap) {
            if (stateObj.IsInAGame)
                RenderBackgroundGoneNotice();
            return;
        }
        // print("render? " + challengeStartTime + ", gt: " + currGameTime);
        if (stateObj.challengeStartTime < 0) return;
        if (stateObj.currGameTime < 0) return;
        if (!stateObj.challengeRunActive) return;
        RenderChatWindow();
        RenderTimer();
        if (stateObj.IsSinglePlayer || stateObj.IsStandard)
            RenderOpponentStatus();
        else if (stateObj.IsTeams) {
            throw('todo: render teams');
        }
        else if (stateObj.IsBattleMode) {
            throw('todo: render battle');
        }
    }

    void RenderTimer() {
        auto duration = stateObj.challengeEndTime - stateObj.challengeStartTime;
        nvg::Reset();
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Bottom);
        nvg::FontFace(nvgFontTimer);
        auto fs = Draw::GetHeight() * 0.06;
        nvg::FontSize(fs);
        auto textPos = vec2(Draw::GetWidth() / 2., Draw::GetHeight() * 0.98);
        vec2 offs = vec2(fs, fs) * 0.05;
        NvgTextWShadow(textPos, offs.x, TimeFormat(duration), vec4(1, 1, 1, 1));
    }

    // works in single player and standard
    void RenderOpponentStatus() {
        auto challengeResult = stateObj.challengeResult;
        auto duration = stateObj.challengeEndTime - stateObj.challengeStartTime;
        if (challengeResult.HasResultFor(stateObj.TheirTeamLeader)) {
            nvg::TextAlign(nvg::Align::Center | nvg::Align::Top);
            nvg::FontFace(nvgFontMessage);
            vec2 textPos = vec2(Draw::GetWidth() / 2., Draw::GetHeight() * 0.03);
            auto fs = Draw::GetHeight() * 0.045;
            nvg::FontSize(fs);
            vec2 offs = vec2(fs, fs) * 0.05;
            auto oppTime = challengeResult.GetResultFor(stateObj.TheirTeamLeader, DNF_TIME);
            auto col = vec4(1, .5, 0, 1);
            string msg = oppTime > DNF_TEST ? stateObj.OpposingLeaderName + " DNF'd"
                : stateObj.OpposingLeaderName + "'s Time: " + Time::Format(challengeResult.GetResultFor(stateObj.TheirTeamLeader));
            NvgTextWShadow(textPos, offs.x, msg, col);
            if (duration > oppTime) {
                textPos += vec2(0, fs);
                NvgTextWShadow(textPos, offs.x, "You lost.", col);
                if (stateObj.opt_AutoDNF > 0) {
                    auto timeLeft = oppTime + stateObj.opt_AutoDNF_ms - duration;
                    textPos += vec2(0, fs);
                    NvgTextWShadow(textPos, offs.x, "Auto DNFing in " + Text::Format("%.1f", 0.001 * timeLeft), col);
                }
            }
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
        if (stateObj.ActiveLeader == TTGSquareState::Unclaimed) return;
        UI::SetNextWindowSize(Draw::GetWidth() * 0.5, Draw::GetHeight() * 0.6, UI::Cond::FirstUseEver);
        UI::PushFont(hoverUiFont);
        if (UI::Begin("Tic Tac GO! ("+stateObj.MyName+")##" + idNonce)) {
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
                if (stateObj.IsGameFinished)
                    client.SendLeave();
                client.SendLeave();
            }
            UI::EndTable();
        }
        UI::Separator();
        S_TTG_HidePlayerEvents = UI::Checkbox("Hide Player Events?", S_TTG_HidePlayerEvents);
        UI::Separator();
        if (UI::BeginChild("##game-log-child")) {
            if (stateObj.gameLog.IsEmpty()) {
                UI::Text("No moves yet.");
            } else {
                for (int i = stateObj.gameLog.Length - 1; i >= 0; i--) {
                    auto evt = stateObj.gameLog[i];
                    if (!S_TTG_HidePlayerEvents || cast<TTGGameEvent_PlayerEvent>(evt) is null) {
                        evt.Draw();
                        UI::Dummy(vec2(0, 8));
                    }
                }
            }
        }
        UI::EndChild();
        UI::PopFont();
    }

    bool IsPlayerConnected(TTGSquareState player) {
        return (stateObj.IsSinglePlayer && player == TTGSquareState::Player2) || client.currentPlayers.Exists(GameInfo.teams[player][0]);
    }

    void DrawPlayer(TTGSquareState player) {
        if (stateObj.ActiveLeader == TTGSquareState::Unclaimed) return;
        auto team = int(player);
        auto playerNum = team + 1;
        bool isMe = player == stateObj.MyTeamLeader;
        UI::PushFont(hoverUiFont);
        UI::Text(IconForPlayer(player) + " -- Player " + playerNum + (isMe ? " (You)" : ""));
        auto nameCol = "\\$" + (stateObj.ActiveLeader == player ? "4b1" : "999");
        string name = stateObj.MyTeamLeader == player ? stateObj.MyLeadersName : stateObj.OpposingLeaderName;
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
            if (stateObj.IsGameFinished) {
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
        auto activeName = stateObj.ActiveLeadersName;
        if (UI::BeginTable("ttg-table-status", 3, UI::TableFlags::SizingStretchSame)) {
            UI::TableSetupColumn("l", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("m", UI::TableColumnFlags::WidthFixed);
            UI::TableSetupColumn("r", UI::TableColumnFlags::WidthStretch);
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::TableNextColumn();
            UI::PushFont(hoverUiFont);
            if (stateObj.IsMyTurn)
                UI::Text(HighlightWin("Your Turn!"));
            else
                UI::Text(activeName + "'s Turn");
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
        if (stateObj.IsGameFinished) {
            string winMsg = "Winner:\n" + activeName;
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

    const string IconForPlayer(TTGSquareState player) {
        if (player == TTGSquareState::Unclaimed) return Icons::QuestionCircleO;
        return player == TTGSquareState::Player1 ? Icons::CircleO : Icons::Kenney::Times;
        // return player == TTGSquareState::Player1 ? Icons::CircleO : Icons::Times;
    }

    void DrawTTGSquare(uint col, uint row, vec2 size) {
        auto sqState = stateObj.GetSquareState(col, row);
        bool squareOpen = sqState.owner == TTGSquareState::Unclaimed;
        string label = squareOpen ? "" : IconForPlayer(sqState.owner);
        string id = "##sq-" + col + "," + row;

        bool isWinning = stateObj.IsGameFinished && stateObj.SquarePartOfWin(int2(col, row));
        bool isBeingChallenged = stateObj.IsInClaimOrChallenge && stateObj.challengeResult.col == col && stateObj.challengeResult.row == row;
        bool ownedByMe = stateObj.SquareOwnedByMe(col, row);
        bool ownedByThem = stateObj.SquareOwnedByThem(col, row);

        UI::PushFont(boardFont);
        bool isDisabled = !stateObj.IsWaitingForMove || not stateObj.IsMyTurn || waitingForOwnMove;
        bool clicked = _SquareButton(label + id, size, col, row, isBeingChallenged, ownedByMe, ownedByThem, isWinning, isDisabled);
        UI::PopFont();

        if (clicked) log_trace('clicked');
        if (clicked && (!ownedByMe || stateObj.IsSinglePlayer)) {
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
        bool mapKnown = stateObj.SquareKnown(col, row);

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
                UI::Text("Challenge " + stateObj.OpposingLeaderName);
            } else if (mapKnown) {
                UI::Text("Win to claim!");
            }

            if (ownedByMe || ownedByThem || mapKnown) {
                UI::Separator();
                auto map = stateObj.GetMap(col, row);
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
        if (!stateObj.GetSquareState(col, row).IsUnclaimed) {
            warn("tried to take an occupied square");
            return;
        }
        waitingForOwnMove = true;
        client.SendPayload("G_TAKE_SQUARE", JsonObject2("col", col, "row", row));
    }

    void ChallengeFor(uint col, uint row) {
        auto sqState = stateObj.GetSquareState(col, row);
        if (sqState.IsUnclaimed) {
            warn("tried to ChallengeFor an unclaimed square");
            return;
        }
        if (sqState.IsOwnedBy(stateObj.MyTeamLeader) && !stateObj.IsSinglePlayer) {
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
                log_trace('hide chat');
            }
        }
        UI::PushFont(hoverUiFont);
        bool changed;
        m_chatMsg = UI::InputText("##ttg-chat-msg"+idNonce, m_chatMsg, changed, UI::InputTextFlags::EnterReturnsTrue);
        if (changed) UI::SetKeyboardFocusHere(-1);
        UI::SameLine();
        if (UI::Button("Send") || changed) {
            startnew(CoroutineFunc(SendChatMsg));
        }
        UI::Separator();
        if (UI::BeginChild("##ttg-chat", vec2(), true, UI::WindowFlags::AlwaysAutoResize)) {
            auto @chat = client.mainChat;
            string chatMsg;
            for (int i = 0; i < client.mainChat.Length; i++) {
                auto thisIx = (int(client.chatNextIx) - i - 1 + chat.Length) % chat.Length;
                auto msg = chat[thisIx];
                if (msg is null) break;
                chatMsg = ColoredString(string(msg['payload']['content']));
                UI::TextWrapped(Time::FormatString("%H:%M", int64(msg['ts'])) + " [ " + HighlightGray(string(msg['from']['username'])) + " ]:\n  " + chatMsg);
                UI::Dummy(vec2(0, 2));
            }
        }
        UI::EndChild();
        UI::PopFont();
    }

    void SendChatMsg() {
        if (m_chatMsg != "" && m_chatMsg.Trim().Length > 0)
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

    bool waitingForOwnMove = false;

    void GameLoop() {
        while (stateObj.IsPreStart) yield();
        // while (ActivePlayer == TTGSquareState::Unclaimed) yield();
        // state = TTGGameState::WaitingForMove;
        while (not stateObj.IsGameFinished && client.IsConnected) {
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
                // auto fromPlayer = gotOwnMessage ? IAmPlayer : TheyArePlayer;
                // lastFrom = fromPlayer;
                stateObj.ProcessMove(msg);
            }
            incomingEvents.RemoveRange(0, incomingEvents.Length);
        }
    }

    // call EndChallengeWindow regardless of what this returns.
    bool BeginChallengeWindow() {
        auto flags = UI::WindowFlags::NoTitleBar
            | UI::WindowFlags::AlwaysAutoResize;
        UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(20, 20));
        UI::PushStyleVar(UI::StyleVar::WindowRounding, 20);
        UI::PushStyleVar(UI::StyleVar::WindowPadding, vec2(20, 20));
        UI::PushStyleColor(UI::Col::WindowBg, challengeWindowBgCol);
        return UI::Begin("ttg-challenge-window-" + idNonce, flags);
    }

    void EndChallengeWindow() {
        UI::End();
        UI::PopStyleColor(1);
        UI::PopStyleVar(3);
    }

    vec4 challengeWindowBgCol = btnChallengeCol * vec4(.3, .3, .3, 1);

    void DrawChallengeWindow() {
        if (!(stateObj.IsInChallenge || stateObj.IsInClaim) && stateObj.challengeEndedAt + 6000 < Time::Now) return;
        if (CurrentlyInMap) return;
        if (stateObj.currMap is null) return;
        if (BeginChallengeWindow()) {
            UI::PushFont(mapUiFont);
            if (stateObj.IsSinglePlayer || stateObj.IsStandard)
                DrawStdChallengeWindow();
            if (stateObj.IsTeams)
                DrawTeamsChallengeWindow();
            if (stateObj.IsBattleMode)
                DrawBattleModeChallengeWindow();
            UI::PopFont();
            UI::Separator();
            DrawThumbnail(stateObj.currTrackIdStr);
        }
        EndChallengeWindow();
    }

    void DrawStdChallengeWindow() {
        auto currMap = stateObj.currMap;
        auto challengeResult = stateObj.challengeResult;
        auto OpposingTLName = stateObj.OpposingLeaderName;
        auto MyName = stateObj.MyLeadersName;
        auto myTeam = stateObj.MyTeamLeader;
        auto theirTeam = stateObj.TheirTeamLeader;
        string challengeStr;
        bool iAmChallenging = challengeResult.challenger == stateObj.MyTeamLeader;
        if (challengeResult.IsClaim) {
            if (iAmChallenging) challengeStr = "Beat " + OpposingTLName + " to claim this map!";
            else challengeStr = "Beat " + OpposingTLName + " to deny their claim!";
        } else {
            if (iAmChallenging) challengeStr = "You are challenging " + OpposingTLName;
            else challengeStr = OpposingTLName + " challenges you!";
        }
        UI::TextWrapped(challengeStr);
        UI::Text("First to finish wins!");
        UI::Text("Restarting does not zero timer!");
        UI::Separator();
        DrawChallengeMapName();
        UI::Separator();
        UI::AlignTextToFramePadding();
        if (challengeResult.IsResolved) {
            UI::Text("-- RESULT --");
            UI::Text(MyName + ": " + FormatChallengeTime(challengeResult.GetResultFor(myTeam)));
            UI::Text(OpposingTLName + ": " + FormatChallengeTime(challengeResult.GetResultFor(theirTeam)));
            UI::AlignTextToFramePadding();
            UI::Text("Winner: " + stateObj.GetLeadersName(challengeResult.Winner));
        } else if (challengeResult.HasResultFor(myTeam)) {
            UI::Text("Waiting for " + OpposingTLName + " to set a time.");
            UI::Text(MyName + ": " + FormatChallengeTime(challengeResult.GetResultFor(myTeam)));
        } else {
            DrawChallengePlayMapButton();
        }
    }

    void DrawChallengeMapName() {
        auto currMap = stateObj.currMap;
        UI::TextWrapped("Map: " + ColoredString(currMap['Name']));
        UI::Text(string(currMap['LengthName']) + " / " + string(currMap['DifficultyName']));
    }

    void DrawTeamsChallengeWindow() {
        auto currMap = stateObj.currMap;
        auto challengeResult = stateObj.challengeResult;
        auto OpposingTLName = stateObj.OpposingLeaderName;
        auto MyName = stateObj.MyLeadersName;
        auto myTeam = stateObj.MyTeamLeader;
        auto theirTeam = stateObj.TheirTeamLeader;
        string challengeStr;
        bool iAmChallenging = challengeResult.challenger == stateObj.MyTeamLeader;
        if (challengeResult.IsClaim) {
            if (iAmChallenging) challengeStr = "Beat Team " + OpposingTLName + " to claim this map!";
            else challengeStr = "Beat Team " + OpposingTLName + " to deny their claim!";
        } else {
            if (iAmChallenging) challengeStr = "Your team challenges Team " + OpposingTLName;
            else challengeStr = "Team " + OpposingTLName + " challenges your team!";
        }
        UI::TextWrapped(challengeStr);
        UI::Text("Score the most points to win!");
        UI::Text("Restarting does not zero timer!");
        UI::Separator();
        DrawChallengeMapName();
        UI::Separator();
        if (challengeResult.IsResolved) {
            // draw winning team
        } else if (challengeResult.IsEmpty) {
            DrawChallengePlayMapButton();
        } else {
            // draw in progress
        }
    }

    void DrawBattleModeChallengeWindow() {
        auto currMap = stateObj.currMap;
        auto challengeResult = stateObj.challengeResult;
        auto OpposingTLName = stateObj.OpposingLeaderName;
        auto MyName = stateObj.MyLeadersName;
        auto myTeam = stateObj.MyTeamLeader;
        auto theirTeam = stateObj.TheirTeamLeader;
        string challengeStr;
        bool iAmChallenging = challengeResult.challenger == stateObj.MyTeamLeader;
        if (challengeResult.IsClaim) {
            if (iAmChallenging) challengeStr = "Beat " + OpposingTLName + " to claim this map!";
            else challengeStr = "Beat " + OpposingTLName + " to deny their claim!";
        } else {
            if (iAmChallenging) challengeStr = "You are challenging " + OpposingTLName;
            else challengeStr = OpposingTLName + " challenges you!";
        }
        UI::TextWrapped(challengeStr);
    }

    void DrawChallengePlayMapButton() {
        auto challengeResult = stateObj.challengeResult;
        if (challengeResult.startTime > Time::Now) {
            auto timeLeft = float(challengeResult.startTime - Time::Now) / 1000.;
            UI::Text("Starting in: " + Text::Format("%.1f", timeLeft));
        } else {
            UI::BeginDisabled(stateObj.disableLaunchMapBtn);
            if (UI::Button("LAUNCH MAP")) {
                startnew(CoroutineFunc(stateObj.RunChallengeAndReportResult));
            }
            UI::EndDisabled();
        }
    }

    const string FormatChallengeTime(int time) {
        if (time >= DNF_TEST) return "DNF";
        return Time::Format(time);
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

#if DEV
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
#endif
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

    TTGMode mode;
    dictionary uidTimes;
    string[][]@ teamUids;
    int totalUids = -1;
    UidRank@[] teamsRanking;


    void Reset() {
        startTime = -1;
        active = false;
    }

    void Activate(uint col, uint row, TTGSquareState challenger, TTGGameState type, string[][] &in teamUids, TTGMode mode) {
        if (active) throw("already active");
        this.col = int(col);
        this.row = int(row);
        active = true;
        player1Time = -1;
        player2Time = -1;
        uidTimes.DeleteAll();
        this.challenger = challenger;
        this.defender = challenger == TTGSquareState::Player1 ? TTGSquareState::Player2 : TTGSquareState::Player1;
        challengeType = type;
        @this.teamUids = teamUids;
        totalUids = teamUids[0].Length + (teamUids.Length == 1 ? 0 : teamUids[1].Length);
        this.mode = mode;
        teamsRanking.Resize(0);
    }

    bool get_IsEmpty() const {
        return player1Time < 0 && player2Time < 0 && uidTimes.GetSize() == 0;
    }

    bool get_IsClaim() const {
        return challengeType == TTGGameState::InClaim;
    }

    bool get_IsChallenge() const {
        return challengeType == TTGGameState::InChallenge;
    }

    bool get_IsResolved() const {
        return ResolvedLegacyMethod || totalUids > 0 && totalUids == uidTimes.GetSize();
    }


    bool get_ResolvedLegacyMethod() const {
        return player1Time > 0 && player2Time > 0;
    }

    TTGSquareState get_Winner() const {
        if (!IsResolved) return TTGSquareState::Unclaimed;
        if (ResolvedLegacyMethod) return WinnerLegacyMethod;
        // todo: details depend on scoring method
        if (mode == TTGMode::Standard) return WinnerStandard;
        if (mode == TTGMode::Teams) return WinnerTeams;
        if (mode == TTGMode::BattleMode) return WinnerBattleMode;
        throw("get_Winner, no mode? should never happen");
        return TTGSquareState::Unclaimed;
    }

    TTGSquareState get_WinnerStandard() const {
        int minTime = DNF_TIME;
        TTGSquareState winningTeam = TTGSquareState::Unclaimed;
        for (int i = 0; i < teamUids.Length; i++) {
            auto currTeam = TTGSquareState(i);
            auto @team = teamUids[i];
            for (int j = 0; j < team.Length; j++) {
                string uid = team[j];
                int time = DNF_TIME;
                //if (!uidTimes.Exists(uid)) continue;
                if (!uidTimes.Get(uid, time)) continue;
                if (time < minTime || ((time == minTime || minTime > DNF_TEST) && currTeam == defender)) {
                    minTime = time;
                    winningTeam = currTeam;
                }
            }
        }
        if (minTime > DNF_TEST) return defender;
        return winningTeam;
    }

    TTGSquareState get_WinnerTeams() const {
        int[] score = {0, 0};
        for (uint i = 0; i < teamsRanking.Length; i++) {
            auto ur = teamsRanking[i];
            auto points = totalUids - i;
            if (ur.time >= DNF_TEST) continue;
            score[ur.team] += points;
        }
        if (score[0] > score[1]) {
            return TTGSquareState::Player1;
        } else if (score[1] > score[0]) {
            return TTGSquareState::Player2;
        }
        return defender;
    }

    void OnNewTime_Teams(const string &in uid, int time, TTGSquareState team) {
        // defenders have priority
        // InsertRankings(teamUids[defender], defender);
        // InsertRankings(teamUids[challenger], challenger);
        InsertRanking(UidRank(uid, time, team));
    }

    // void InsertRankings(string[] &in theTeam, TTGSquareState team) {
    //     for (uint i = 0; i < theTeam.Length; i++) {
    //         auto uid = theTeam[i];
    //         auto time = GetResultFor(uid);
    //         if (time < 0) continue;
    //         InsertRanking(UidRank(uid, time, team));
    //     }
    // }

    void InsertRanking(UidRank@ ur) {
        for (uint i = 0; i < teamsRanking.Length; i++) {
            auto other = teamsRanking[i];
            if (ur.time < other.time) {
                teamsRanking.InsertAt(i, ur);
                return;
            } else if (ur.time == other.time && ur.team == defender && other.team == challenger) {
                teamsRanking.InsertAt(i, ur);
                return;
            }
        }
        // if we get here, then we haven't inserted it yet
        teamsRanking.InsertLast(ur);
    }

    TTGSquareState get_WinnerBattleMode() const {
        // return TTGSquareState::Unclaimed;
        return WinnerStandard;
    }

    TTGSquareState get_WinnerLegacyMethod() const {
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

    // force and end to the round, filling in any un-filled scores
    void ForceEnd() {
        if (player1Time <= 0) player1Time = DNF_TIME;
        if (player2Time <= 0) player2Time = DNF_TIME;
        DnfUnfinishedForTeam(teamUids[0], TTGSquareState::Player1);
        DnfUnfinishedForTeam(teamUids[1], TTGSquareState::Player2);
    }

    void DnfUnfinishedForTeam(string[] &in thisTeamsUids, TTGSquareState team) {
        for (uint i = 0; i < thisTeamsUids.Length; i++) {
            auto uid = thisTeamsUids[i];
            if (!uidTimes.Exists(uid))
                SetPlayersTime(uid, DNF_TIME, team);
        }
    }

    // when not in single player
    void SetPlayersTime(const string &in uid, int time, TTGSquareState team) {
        uidTimes[uid] = time;
        if (mode == TTGMode::Teams) {
            OnNewTime_Teams(uid, time, team);
        }
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

    bool HasResultFor(const string &in uid) const {
        return uidTimes.Exists(uid);
        // throw('has result for uid unimpl');
        // return false;
    }

    bool HasResultFor(TTGSquareState player) const {
        if (mode == TTGMode::SinglePlayer) {
            if (player == TTGSquareState::Unclaimed) throw("should never pass unclaimed, here");
            return (player == TTGSquareState::Player1 && HavePlayer1Res) || (player == TTGSquareState::Player2 && HavePlayer2Res);
        } else if (mode == TTGMode::Standard) {
            return HasResultFor(teamUids[player][0]);
        }
        throw("Don't call this from teams or battle mode");
        return false;
    }

    int GetResultFor(TTGSquareState player, int _default = -1) const {
        if (player == TTGSquareState::Unclaimed) throw("should never pass unclaimed, here");
        if (mode == TTGMode::Standard) return GetResultFor(teamUids[player][0], _default);
        auto ret = player == TTGSquareState::Player1 ? player1Time : player2Time;
        if (ret < 0) return _default;
        return ret;
    }

    int GetResultFor(const string &in uid, int def = -1) const {
        int ret;
        if (uidTimes.Get(uid, ret)) return ret;
        return def;
    }

    int get_ChallengerTime() const {
        return GetResultFor(challenger);
    }

    int get_DefenderTime() const {
        return GetResultFor(defender);
    }
}


class UidRank {
    string uid;
    uint time;
    TTGSquareState team;

    UidRank(const string &in uid, uint time, TTGSquareState team) {
        this.uid = uid;
        this.time = time;
        this.team = team;
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
    TicTacGoState@ ttg;
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

    TTGGameEvent_MapResult(TicTacGoState@ ttg, TTGGameEventType type, ChallengeResultState@ cr, int moveNumber) {
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
        string cName = ttg.GetLeadersName(Challenger);
        string dName = ttg.GetLeadersName(Defender);
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
