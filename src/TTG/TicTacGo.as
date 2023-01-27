enum TTGSquareState {
    Unclaimed = -1,
    Player1 = 0,
    Player2 = 1
}

const int AUTO_DNF_TIMEOUT = 10000;
// DNFs are signaled with this time. It's 24hrs + 999ms;
const int DNF_TIME = 86400999;
const int DNF_TEST = 86400000;

// loaded in Main()
UI::Font@ boardFont = null;
UI::Font@ mapUiFont = null;
UI::Font@ hoverUiFont = null;
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
    string clientNonce = Crypto::RandomBase64(5);

    TicTacGoState@ stateObj;

    Json::Value@[] incomingEvents;

    CoroutineFunc@ OnRematch = null;
    string rematchJoinCode;
    string rematchFromUser;
    bool rematchBeingCreated;

    TicTacGo(Game::Client@ client, bool setRandomNonce = false) {
        // if (setRandomNonce)
        //     idNonce = client.clientUid;
            // idNonce = tostring(Math::Rand(0, 99999999));
        @this.client = client;
        @this.stateObj = TicTacGoState(client);
        client.AddMessageHandler("PLAYER_LEFT", CGF::MessageHandler(MsgHandler_PlayerEvent));
        client.AddMessageHandler("PLAYER_JOINED", CGF::MessageHandler(MsgHandler_PlayerEvent));
        client.AddMessageHandler("LOBBY_LIST", CGF::MessageHandler(MsgHandler_Ignore));
        client.AddMessageHandler("REMATCH_ROOM_CREATED", CGF::MessageHandler(MsgHandler_RematchRoomCreated));
        client.AddMessageHandler("GM_REMATCH_ROOM_CREATED", CGF::MessageHandler(MsgHandler_GmRematchRoomCreated));
        client.AddMessageHandler("G_REMATCH_INIT", CGF::MessageHandler(MsgHandler_GRematchInit));
        client.AddMessageHandler("GAME_REPLAY_START", CGF::MessageHandler(MsgHandler_OnGameStartEvent));
        trace('created TTG client with nonce/id: ' + clientNonce);
    }

    const string get_idNonce() {
        return client.clientUid;
    }

    // used by debug client
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
        if (client is null) return true;
        if (!client.IsInGame) return true;
        string type = j['type'];
        bool addToLog = type == "PLAYER_LEFT" || type == "PLAYER_JOINED";
        if (addToLog) stateObj.gameLog.InsertLast(TTGGameEvent_PlayerEvent(type, j['payload']));
        return true;
    }

    bool MsgHandler_Ignore(Json::Value@ j) {
        if (client is null) return true;
        return true;
    }

    bool MsgHandler_RematchRoomCreated(Json::Value@ j) {
        if (client is null) return true;
        // if (!client.IsInGame) return true;
        rematchJoinCode = j['payload']['join_code'];
        rematchFromUser = j['payload']['by']['username'];
        startnew(CoroutineFunc(OnClickRematchAccept));
        return true;
    }

    bool MsgHandler_GmRematchRoomCreated(Json::Value@ j) {
        if (client is null) return true;
        warn("GM room created msg");
        // if (!client.IsInGame) return true;
        rematchJoinCode = j['payload']['join_code'];
        rematchFromUser = j['payload']['by']['username'];
        return true;
    }

    uint lastRematchAccept = 0;
    void OnClickRematchAccept() {
        if (lastRematchAccept + 500 > Time::Now) return;
        // back to lobby, then join room
        if (rematchJoinCode.Length == 0) return;
        string _jc = rematchJoinCode;
        rematchJoinCode = "";
        lastRematchAccept = Time::Now;
        yield();
        client.SendLeave();
        yield();
        client.SendLeave();
        yield();
        client.JoinRoomViaCode(_jc);
        // returning to menu bugs and leaves twice
        // startnew(ReturnToMenu);
    }

    void _CallOnRematch() {
        if (OnRematch !is null) {
            OnRematch();
        }
    }

    bool MsgHandler_GRematchInit(Json::Value@ j) {
        if (client is null) return true;
        // if (!client.IsInGame) return true;
        // only admins/mods can start this
        if (client.IsPlayerAdminOrMod(j['from']['uid']))
            rematchBeingCreated = true;
        return true;
    }
    bool MsgHandler_OnGameStartEvent(Json::Value@ j) {
        if (client is null) return true;
        rematchJoinCode = "";
        rematchBeingCreated = false;
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
        stateObj.OnGameStart();
        startnew(ReturnToMenu);
        startnew(CoroutineFunc(OnGameStartCoro));
    }

    void OnGameStartCoro() {
        AwaitManialinkTitleReady();
        while (stateObj.IsPreStart) yield();
        startnew(CoroutineFunc(GameLoop));
        startnew(CoroutineFunc(JoinClubRoom));
        // startnew(CoroutineFunc(BlackoutLoop));
    }

    void OnGameEnd() {
        stateObj.OnGameEnd();
        yield();
    }

    void Render() {
        RenderForceEndMaybe();
        if (!CurrentlyInMap) {
            return;
        }
        // print("render? " + challengeStartTime + ", gt: " + currGameTime);
        if (stateObj.challengeStartTime < 0) return;
        if (stateObj.currGameTime < 0) return;
        if (!stateObj.challengeRunActive) return;
        if (stateObj.IsPreStart) return;
        if (!stateObj.IsInServer)
            RenderChatWindow();
        RenderDNFButton();
        RenderTimer();
        RenderLeavingChallenge();
        if (stateObj.IsSinglePlayer || stateObj.IsStandard)
            RenderOpponentStatus();
        else if (stateObj.IsTeams) {
            RenderTeamsScoreBoard(stateObj.challengeResult);
            if (!RenderAutoDnf()) {
                RenderYourScore();
            }
        }
        else if (stateObj.IsBattleMode) {
            RenderBattleModeScoreBoard(stateObj.challengeResult);
            if (!RenderAutoDnf()) {
                RenderYourScore();
            }
        }
    }

    protected uint forceEndWaitingTime = 30000;
    protected uint lastForceEndSent = 0;
    void RenderForceEndMaybe() {
        if (stateObj.IsPreStart || stateObj.IsWaitingForMove || stateObj.IsGameFinished) return;
        // if a challenge is active
        if (!stateObj.challengeResult.active) return;
        // only for admins/mods
        if (!client.IsPlayerAdminOrMod(client.clientUid)) return;
        // if we're resolved and it's been more than 15s since the last force end, send a force end automatically
        if (stateObj.challengeResult.IsResolved && lastForceEndSent + 15000 < Time::Now) {
            warn("Auto-sending force end");
            stateObj.SendForceEnd();
            lastForceEndSent = Time::Now;
        }
        // wait 30 s before showing the main UI
        auto fr = stateObj.challengeResult.firstResultAt;
        if (fr <= 0 || Time::Now - fr < int(forceEndWaitingTime)) return;
        UI::SetNextWindowPos(Draw::GetWidth() - 400, 50, UI::Cond::Appearing);
        UI::PushFont(mapUiFont);
        if (UI::Begin("Force End Round", UI::WindowFlags::NoCollapse | UI::WindowFlags::NoResize | UI::WindowFlags::NoMove | UI::WindowFlags::AlwaysAutoResize)) {
            UI::Text("Round gone on too long?");
            UI::BeginDisabled(lastForceEndSent + 3000 > Time::Now);
            if (UI::Button("Force End")) {
                stateObj.SendForceEnd();
                lastForceEndSent = Time::Now;
            }
            UI::EndDisabled();
            uint numDisconnected = GameInfo.players.Length - client.currentPlayers.GetSize();
            if (numDisconnected > 0) {
                UI::PushFont(hoverUiFont);
                UI::AlignTextToFramePadding();
                UI::Text(tostring(numDisconnected) + " players disconnected.");
                DrawShowAllPlayers();
                UI::PopFont();
            }
        }
        UI::End();
        UI::PopFont();
    }

    void RenderTimer() {
        auto duration = stateObj.challengeEndTime - stateObj.challengeStartTime;
        nvg::Reset();
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Bottom);
        nvg::FontFace(nvgFontTimer);
        auto fs = Draw::GetHeight() * 0.06;
        nvg::FontSize(fs);
        auto textPos = vec2(Draw::GetWidth() / 2., Draw::GetHeight() * 0.98);
        // vec2 offs = vec2(fs, fs) * 0.05;
        NvgTextWShadow(textPos, fs * 0.05, TimeFormat(duration), vec4(1, 1, 1, 1));
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
            auto oppTime = challengeResult.GetResultFor(stateObj.TheirTeamLeader, DNF_TIME);
            auto col = vec4(1, .5, 0, 1);
            string msg = oppTime > DNF_TEST ? stateObj.OpposingLeaderName + " DNF'd"
                : stateObj.OpposingLeaderName + "'s Time: " + Time::Format(challengeResult.GetResultFor(stateObj.TheirTeamLeader));
            NvgTextWShadow(textPos, fs * 0.05, msg, col);
            if (duration > oppTime) {
                textPos += vec2(0, fs);
                NvgTextWShadow(textPos, fs * 0.05, "You lost.", col);
                auto timeLeft = oppTime + stateObj.opt_AutoDNF_ms - duration;
                textPos += vec2(0, fs);
                RenderAutoDnfInner(textPos, fs, timeLeft, col);
            }
        }
    }

    void RenderYourScore() {
        auto cr = stateObj.challengeResult;
        if (cr.HasResultFor(client.clientUid) && !cr.IsResolved) {
            nvg::TextAlign(nvg::Align::Center | nvg::Align::Top);
            nvg::FontFace(nvgFontMessage);
            vec2 textPos = vec2(Draw::GetWidth() / 2., Draw::GetHeight() * 0.03);
            auto fs = Draw::GetHeight() * 0.045;
            nvg::FontSize(fs);
            auto myTime = cr.GetResultFor(client.clientUid, 83456); // 1:23.456
            auto col = vec4(1, 1, 1, 1);
            string msg = "Your Time: " + Time::Format(myTime);
            NvgTextWShadow(textPos, fs * 0.05, msg, col);
        }
    }

    void RenderAutoDnfInner(vec2 textPos, float fs, uint timeLeft, vec4 col) {
        // if we should exit the challenge, don't show the autodnf msg
        if (stateObj.shouldExitChallenge) return;
        if (stateObj.opt_AutoDNF > 0) {
            NvgTextWShadow(textPos, fs * .05, "Auto DNFing in", col);
            NvgTextWShadow(textPos + vec2(0, fs * 1.2), fs * .05, Text::Format("%.1f", 0.001 * float(timeLeft)), col);
        }
    }

    bool RenderAutoDnf() {
        if (stateObj.challengeResult.ranking.Length == 0) return false;
        if (stateObj.challengeResult.HasResultFor(client.clientUid)) return false;
        auto bestTime = int(stateObj.challengeResult.ranking[0].time);
        if (bestTime <= 0 || bestTime > DNF_TEST) return false;
        auto duration = stateObj.challengeEndTime - stateObj.challengeStartTime;
        if (duration < bestTime) return false;
        auto timeLeft = bestTime + stateObj.opt_AutoDNF_ms - duration;
        vec2 screen = vec2(Draw::GetWidth(), Draw::GetHeight());
        vec2 pos = screen * vec2(.5, .15);
        float fs = screen.y * 0.04;
        nvg::Reset();
        nvg::FontFace(nvgFontMessage);
        nvg::FontSize(fs);
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);
        RenderAutoDnfInner(pos, fs, timeLeft, vec4(1, .5, 0, 1));
        return true;
    }

    void RenderLeavingChallenge(vec4 col = vec4(1, 1, 1, 1)) {
        if (!stateObj.shouldExitChallenge || !CurrentlyInMap) return;
        if (stateObj.IsGameFinished) return;
        float timeLeft = float(stateObj.shouldExitChallengeTime) - Time::Now;
        // log_trace('render leaving. time left: ' + timeLeft);
        vec2 pos = vec2(Draw::GetWidth(), Draw::GetHeight()) / 2.;
        float fs = Draw::GetHeight() * 0.056;
        nvg::Reset();
        nvg::FontFace(nvgFontMessage);
        nvg::FontSize(fs);
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);
        NvgTextWShadow(pos, fs * .05, stateObj.IsInServer ? "Challenge Over." : "Challenge Over. Exiting in", col);
        NvgTextWShadow(pos + vec2(0, fs * 1.2), fs * .05, Text::Format("%.1f", 0.001 * Math::Max(timeLeft, 0)), col);
    }

    int dnfBtnWindowFlags = UI::WindowFlags::NoTitleBar
        | UI::WindowFlags::AlwaysAutoResize;

    void RenderDNFButton() {
        // don't render if we've submitted a result already
        if (!stateObj.IsSinglePlayer && stateObj.challengeResult.HasResultFor(client.clientUid))
            return;
        vec2 size = vec2(200, 140);
        auto btnSize = size / 2;
        UI::SetNextWindowSize(int(size.x), int(size.y), UI::Cond::Always);
        UI::SetNextWindowPos(Draw::GetWidth() - int(size.x) - 50, (Draw::GetHeight() - int(size.y)) / 2, UI::Cond::FirstUseEver);
        UI::PushFont(mapUiFont);
        if (UI::Begin("dnf window in server", dnfBtnWindowFlags)) {
            if (UI::BeginChild("dnf window inner", UI::GetContentRegionAvail())) {
                auto region = UI::GetContentRegionAvail();
                UI::SetCursorPos((region - btnSize) / 2);
                if (UI::Button("DNF##dnf-btn"+idNonce, btnSize)) {
                    stateObj.ReportChallengeResult(DNF_TIME);
                    if (stateObj.IsSinglePlayer) stateObj.EndChallenge();
                }
            }
            UI::EndChild();
        }
        UI::End();
        UI::PopFont();
    }

    int chatWindowFlags = UI::WindowFlags::NoTitleBar
        | UI::WindowFlags::None;

    void RenderChatWindow() {
        if (S_TTG_HideChat) return;
        bool isOpen = !S_TTG_HideChat;
        UI::SetNextWindowSize(400, 250, UI::Cond::FirstUseEver);
        UI::SetNextWindowPos(100, Draw::GetHeight() - 250 - 100, UI::Cond::FirstUseEver);
        if (UI::Begin("chat window" + idNonce, isOpen, chatWindowFlags)) {
            // draw a child so buttons work
            if (UI::BeginChild("chat window child" + idNonce)) {
                DrawChat(true, 0);
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
        // we never want to render the TTG game interface in a local map.
        if (CurrentlyInMap && !client.roomInfo.use_club_room) return;
        // uninitialized
        if (stateObj.ActiveLeader == TTGSquareState::Unclaimed) return;

        if (CurrentlyInMap && client.roomInfo.use_club_room) {
            // if we are in a map and using a club room, don't show the interface when we're in a claim or challenge and about to race
            if (stateObj.IsInClaimOrChallenge && stateObj.hideChallengeWindowInServer) {
                return;
            }
        }

        if (rematchJoinCode.Length > 0) {
            DrawRematchPromptWindow();
        }
        DrawTtgMainWindow();
        DrawChallengeWindow();
    }

    void DrawRematchPromptWindow() {
        if (UI::Begin("rematch window", UI::WindowFlags::NoTitleBar | UI::WindowFlags::AlwaysAutoResize)) {
            UI::PushFont(mapUiFont);
            UI::AlignTextToFramePadding();
            UI::Text("Rematch?");
            if (UI::Button("Accept##rematch")) {
                startnew(CoroutineFunc(OnClickRematchAccept));
            }
            UI::SameLine();
            UI::Dummy(vec2(30, 30));
            UI::SameLine();
            if (UI::Button("Leave##rematch")) {
                // startnew(ReturnToMenu);
                client.SendLeave();
                client.SendLeave();
            }
            UI::PopFont();
        }
        UI::End();
    }

    void DrawTtgMainWindow() {
        UI::SetNextWindowSize(Draw::GetWidth() / 2, Draw::GetHeight() * 3 / 5, UI::Cond::FirstUseEver);
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
    }

    // player 1 col
    void DrawLeftCol(vec2 size) {
        if (UI::BeginChild("ttg-p1", size, true)) {
            DrawPlayer(TTGSquareState::Player1);
            UI::Dummy(vec2(0, 8));
            DrawPlayer(TTGSquareState::Player2);
            DrawLeaveGameOrRematch();
            DrawGameDebugInfo();
            if (GameInfo.players.Length > 2) {
                UI::Dummy(vec2(0, 8));
                DrawShowAllPlayers();
            }
            UI::Dummy(vec2(0, 8));
            DrawChat();
        }
        UI::EndChild();
    }

    void DrawGameDebugInfo() {
        if (S_LocalDev || S_TTG_DrawGameDebugInfo) {
            if (UI::CollapsingHeader("Game Debug Info")) {
                UI::Text(tostring(stateObj.state));
                UI::Text(stateObj.currMap is null ? "Curr Map: null" : ("Map: " + ColoredString(string(stateObj.currMap['Name']))));
                UI::Text("In Map: " + tostring(CurrentlyInMap));
            }
        }
    }

    void DrawShowAllPlayers() {
        if (TtgCollapsingHeader("Show All Players")) {
            vec4 colT1 = GetLightColorForTeam(TTGSquareState::Player1);
            vec4 colT2 = GetLightColorForTeam(TTGSquareState::Player2);
            for (uint i = 0; i < GameInfo.players.Length; i++) {
                User@ user = GameInfo.players[i];
                bool t2Leader = i == GameInfo.teams[0].Length;
                if (t2Leader) {
                    UI::Dummy(vec2(0, 0));
                }
                UI::PushStyleColor(UI::Col::Text, i < GameInfo.teams[0].Length ? colT1 : colT2);
                Indent(i == 0 || t2Leader ? 1 : 2);
                UI::Text(user.username);
                UI::PopStyleColor();
                if (!IsPlayerConnected(user.uid)) {
                    UI::SameLine();
                    UI::Text("  \\$f81(DCed)");
                }
            }
        }
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
                if (stateObj.IsInServer)
                    startnew(ReturnToMenu);
                if (client.IsInGame && stateObj.IsGameFinished)
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
        if (GameInfo is null) return false;
        return (stateObj.IsSinglePlayer) || client.currentPlayers.Exists(GameInfo.teams[player][0]);
    }

    bool IsPlayerConnected(const string &in uid) {
        return (stateObj.IsSinglePlayer) || client.currentPlayers.Exists(uid);
    }

    void DrawPlayer(TTGSquareState player) {
        if (stateObj.ActiveLeader == TTGSquareState::Unclaimed) return;
        auto team = int(player);
        auto playerNum = team + 1;
        bool isMe = player == stateObj.MyTeamLeader;
        UI::PushFont(hoverUiFont);
        UI::PushStyleColor(UI::Col::Text, GetLightColorForTeam(player));
        UI::Text(IconForPlayer(player) + " -- Player " + playerNum + (isMe ? " (You)" : ""));
        UI::PopStyleColor();
        auto nameCol = "\\$" + (stateObj.ActiveLeader == player ? "4b1" : "999");
        string name = stateObj.MyTeamLeader == player ? stateObj.MyLeadersName : stateObj.OpposingLeaderName;
        UI::Text(nameCol + name);
        if (!IsPlayerConnected(player)) {
            UI::SameLine();
            UI::Text("\\$ea4 (Disconnected)");
        }
        UI::PopFont();
    }

    void DrawLeaveGameOrRematch() {
        // do nothing if the game isn't finished
        if (!stateObj.IsGameFinished) return;
        UI::Dummy(vec2(0, 15));
        UI::PushFont(hoverUiFont);
        if (rematchJoinCode.Length == 0 && client.IsPlayerAdminOrMod(client.clientUid)) {
            if (UI::Button("Rematch##new-game")) {
                client.SendPayload("G_REMATCH_INIT");
                _CallOnRematch();
            }
        } else {
            UI::AlignTextToFramePadding();
            if (rematchJoinCode.Length == 0) {
                UI::Text(rematchBeingCreated ? "Rematch being prepared..." : "Awaiting rematch request...");
            } else {
                if (UI::Button("Accept Rematch##lhs")) {
                    startnew(CoroutineFunc(OnClickRematchAccept));
                }
            }
        }
        if (UI::Button("Leave##game-lhs")) {
            // once for game, once for room
            startnew(ReturnToMenu);
            client.SendLeave();
            client.SendLeave();
        }
        UI::PopFont();
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
        bool playerHasInitiative = stateObj.IsMyTurn && stateObj.IAmALeader && stateObj.IsWaitingForMove;
        if (playerHasInitiative)
            UI::PushStyleColor(UI::Col::ChildBg, vec4(.3, 1, 0, Math::Sin(float(Time::Now) / 350.) * .3 + .3));
        if (UI::BeginChild("ttg-child-status", vec2(size.x, UI::GetTextLineHeightWithSpacing()))) {
            if (UI::BeginTable("ttg-table-status", 3, UI::TableFlags::SizingStretchSame)) {
                UI::TableSetupColumn("l", UI::TableColumnFlags::WidthStretch);
                UI::TableSetupColumn("m", UI::TableColumnFlags::WidthFixed);
                UI::TableSetupColumn("r", UI::TableColumnFlags::WidthStretch);
                UI::TableNextRow();
                UI::TableNextColumn();
                UI::TableNextColumn();
                UI::PushFont(hoverUiFont);
                bool battleForCenter = stateObj.opt_FirstRoundForCenter && stateObj.turnCounter == 0;
                if (battleForCenter)
                    UI::Text("Battle for the Center!");
                else if (stateObj.IsMyTurn)
                    UI::Text(HighlightWin(stateObj.IAmALeader ? "Your Turn!" : "Your Leader's Turn!"));
                else
                    UI::Text(activeName + "'s Turn");
                UI::PopFont();
                UI::EndTable();
            }
        }
        UI::EndChild();
        UI::PopStyleColor(playerHasInitiative ? 1 : 0);
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
        // return player == TTGSquareState::Player1 ? Icons::CircleO : Icons::Kenney::Times;
        return player == TTGSquareState::Player1 ? Icons::CircleO : Icons::Times;
    }

    void DrawTTGSquare(int col, int row, vec2 size) {
        auto sqState = stateObj.GetSquareState(col, row);
        bool squareOpen = sqState.owner == TTGSquareState::Unclaimed;
        string label = squareOpen ? "" : IconForPlayer(sqState.owner);
        string id = "##sq-" + col + "," + row;

        bool isWinning = stateObj.IsGameFinished && stateObj.SquarePartOfWin(int2(col, row));
        bool isBeingChallenged = stateObj.IsInClaimOrChallenge && stateObj.challengeResult.col == col && stateObj.challengeResult.row == row;
        bool ownedByMe = stateObj.SquareOwnedByMe(col, row);
        bool ownedByThem = stateObj.SquareOwnedByThem(col, row);

        bool isDisabled = ownedByMe || !stateObj.IsWaitingForMove || not stateObj.IsMyTurn || waitingForOwnMove || !stateObj.IAmALeader;
        isDisabled = isDisabled || (stateObj.opt_CannotImmediatelyRepick && stateObj.WasPriorSquare(col, row));

        UI::PushFont(boardFont);
        bool clicked = _SquareButton(label + id, size, col, row, isBeingChallenged, ownedByMe, ownedByThem, isWinning, isDisabled);
        UI::PopFont();

        if (clicked) log_trace('clicked');
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
            auto coordName = TTG_SquareName(col, row);
            if (ownedByMe) {
                // button disabled so never hovers
                UI::Text(coordName + " Claimed by You");
            } else if (ownedByThem) {
                UI::Text(coordName + " Challenge " + stateObj.OpposingLeaderName);
            } else if (mapKnown) {
                UI::Text(coordName + " Win to claim!");
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
    void DrawChat(bool drawHeading = true, float minChatChildHeight = 200.) {
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
        auto cra = UI::GetContentRegionAvail();
        if (UI::BeginChild("##ttg-chat", vec2(0, Math::Max(minChatChildHeight, cra.y)), true, UI::WindowFlags::AlwaysAutoResize)) {
            auto @chat = client.mainChat;
            string chatMsg;
            for (int i = 0; i < int(client.mainChat.Length); i++) {
                auto thisIx = (int(client.chatNextIx) - i - 1 + chat.Length) % chat.Length;
                auto msg = chat[thisIx];
                if (msg is null) break;
                chatMsg = ColoredString(string(msg['payload']['content']));
                string username = string(msg['from']['username']);
                string prefix;
                if (client.IsInGame) {
                    prefix = IconForPlayer(stateObj.UidToTeam(string(msg['from']['uid']))) + " ";
                }
                UI::TextWrapped(Time::FormatString("%H:%M", int64(msg['ts'])) + " [ " + prefix + HighlightGray(username) + " ]:\n  " + chatMsg);
                UI::Dummy(vec2(0, 2));
            }
        }
        UI::EndChild();
        UI::PopFont();
    }

    void SendChatMsg() {
        if (m_chatMsg != "")
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

    void JoinClubRoom() {
        if (client is null) return;
        if (!client.roomInfo.use_club_room) return;
        while (client.IsConnected && client.roomInfo.join_link.Length == 0) yield();
        if (!client.roomInfo.join_link.StartsWith("#")) {
            NotifyWarning("Tried to join club room but join link empty or invalid.");
            return;
        }
        LoadJoinLink(client.roomInfo.join_link);
        // wait for us to join the server
        if (client is null) return;
        while (client.IsInGame && !CurrentlyInMap) yield();
        auto app = cast<CGameManiaPlanet>(GetApp());
        while (app.Network.ClientManiaAppPlayground is null || app.Network.ClientManiaAppPlayground.UILayers.Length < 19) yield();
        yield();
        // this is true when we're in the room and between maps
        while (app.Switcher.ModuleStack.Length == 0 || cast<CSmArenaClient>(app.Switcher.ModuleStack[0]) !is null) yield();
        // something else is active, prbs the menu
        // if we're in a game currently, then we should leave the game UI so that we can rejoin and thus rejoin the server
        if (client is null) return;
        if (client.IsInGame && client.IsConnected) {
            yield();
            sleep(1000);
            yield();
            if (client.IsInGame && client.IsConnected) {
                client.SendLeave();
            }
        }
    }

    void BlackoutLoop() {
        // if (!stateObj.IsInServer) return;
        // while (!client.IsInGame) yield();
        // auto app = cast<CGameManiaPlanet>(GetApp());
        // while (client.IsConnected && client.IsInGame) {
        //     yield();
        //     if (app.CurrentPlayground is null) continue;
        //     app.CurrentPlayground.GameTerminals_IsBlackOut = stateObj.ShouldBlackout();
        // }
        // if (app.CurrentPlayground !is null) {
        //     app.CurrentPlayground.GameTerminals_IsBlackOut = false;
        // }
    }

    void GameLoop() {
        while (stateObj.IsPreStart) {
            yield();
        }
        while (client.IsConnected && client.IsInGame) {
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
                if (fromUser.GetType() == Json::Type::Object) {
                    // int seq = msg['seq'];
                    gotOwnMessage = client.clientUid == string(fromUser['uid']);
                    if (gotOwnMessage) waitingForOwnMove = false;
                }
                // auto fromPlayer = gotOwnMessage ? IAmPlayer : TheyArePlayer;
                // lastFrom = fromPlayer;
                // try {
                if (client.IsInGame)
                    stateObj.ProcessMove(msg);
                // } catch {
                    // warn("Exception processing move: " + getExceptionInfo());
                    // warn("The move: " + Json::Write(msg));
                // }
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
        if (!stateObj.IsInClaimOrChallenge && stateObj.challengeEndedAt + 6000 < Time::Now) return;
        if (CurrentlyInMap && !client.roomInfo.use_club_room) return;
        // trace('DrawChallengeWindow');
        if (stateObj.currMap is null) return;
        // don't draw it after the challenge starts
        if (stateObj.hideChallengeWindowInServer && (stateObj.IsSinglePlayer || !stateObj.challengeResult.HasResultFor(client.clientUid))) return;
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
        // auto currMap = stateObj.currMap;
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
        // auto currMap = stateObj.currMap;
        auto challengeResult = stateObj.challengeResult;
        auto OpposingTLName = stateObj.OpposingLeaderName;
        // auto MyName = stateObj.MyLeadersName;
        // auto myTeam = stateObj.MyTeamLeader;
        // auto theirTeam = stateObj.TheirTeamLeader;
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
        if (!challengeResult.IsResolved && !challengeResult.HasResultFor(client.clientUid)) {
            DrawChallengePlayMapButton();
        } else {
            UITeamsScoreBoard(stateObj.challengeResult);
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
            if (iAmChallenging) challengeStr = "Beat Team " + OpposingTLName + " to claim this map!";
            else challengeStr = "Beat Team " + OpposingTLName + " to deny their claim!";
        } else {
            if (iAmChallenging) challengeStr = "You are challenging Team " + OpposingTLName;
            else challengeStr = "Team " + OpposingTLName + " challenges you!";
        }
        UI::TextWrapped(challengeStr);
        UI::Text("First team to " + challengeResult.finishesToWin + " finishes wins!");
        UI::Text("Restarting does not zero timer!");
        UI::Separator();
        DrawChallengeMapName();
        UI::Separator();
        if (!challengeResult.IsResolved && !challengeResult.HasResultFor(client.clientUid)) {
            DrawChallengePlayMapButton();
        } else {
            UIBattleModeScoreBoard(stateObj.challengeResult);
        }
    }

    void DrawChallengePlayMapButton() {
        if (client.roomInfo.use_club_room) {
            // no play button, just auto voting / server mgmt
            return;
        }
        auto challengeResult = stateObj.challengeResult;
        if (challengeResult.startTime > int(Time::Now)) {
            auto timeLeft = float(challengeResult.startTime - Time::Now) / 1000.;
            UI::AlignTextToFramePadding();
            UI::Text("Starting in: " + Text::Format("%.1f", timeLeft));
        } else {
            UI::BeginDisabled(stateObj.disableLaunchMapBtn);
            if (UI::Button("LAUNCH MAP##" + challengeResult.id)) {
                startnew(CoroutineFunc(stateObj.StartLocalChallengeFromButton));
            }
            UI::EndDisabled();
        }
        if (true) { // ! single player, ! dev mode
            UI::SameLine();
            UI::Dummy(vec2(8, 0));
            UI::SameLine();
            S_TTG_AutostartMap = UI::Checkbox("Auto?", S_TTG_AutostartMap);
        }
#if DEV
        if (stateObj.IsSinglePlayer)
#else
        if (client.InLocalDevMode)
#endif
        {
            UI::PushFont(hoverUiFont);
            if (UI::Button("Cheat (10min)")) {
                stateObj.ReportChallengeResult(1000 * 60 * 10);
            }
            if (UI::Button("Cheat (20min)")) {
                stateObj.ReportChallengeResult(1000 * 60 * 20);
            }
            UI::PopFont();
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




enum TTGGameEventType {
    ClaimFail = 2,
    ClaimWin = 3,
    ChallengeWin = 4,
    ChallengeFail = 5,
}

interface TTGGameEvent {
    void Draw();
}


class TTGGameEvent_ForceEnd : TTGGameEvent {
    string msg;
    TTGGameEvent_ForceEnd(const string &in name, const string &in uid) {
        msg = name + " \\$<\\$4afforce ended\\$> the round. (uid=" + uid.SubStr(0, 6) + "...)";
    }

    void Draw() {
        UI::TextWrapped(msg);
    }
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

class TTGGameEvent_StartingForCenter : TTGGameEvent {
    void Draw() {
        UI::TextWrapped("Battle for the center square!");
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


TTGGameEvent@ TTGGameEvent_ResultForMode(TicTacGoState@ ttg, TTGGameEventType type, ChallengeResultState@ cr, int moveNumber) {
    if (ttg.IsSinglePlayer || ttg.IsStandard) {
        return TTGGameEvent_StdResult(ttg, type, cr, moveNumber);
    } else if (ttg.IsTeams) {
        return TTGGameEvent_TeamsResult(ttg, type, cr, moveNumber);
    } else if (ttg.IsBattleMode) {
        return TTGGameEvent_BattleResult(ttg, type, cr, moveNumber);
    }
    throw("Unknown game mode. " + tostring(ttg.mode));
    return null;
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
    string msg;
    string cName;
    string dName;
    ChallengeResultState@ cr;
    uint turnCount;

    TTGGameEvent_MapResult(TicTacGoState@ ttg, TTGGameEventType type, ChallengeResultState@ cr, int moveNumber) {
        @this.ttg = ttg;
        this.turnCount = turnCount;
        Type = type;
        @this.cr = cr;
        Challenger = cr.challenger;
        Defender = cr.defender;
        xy = int2(cr.col, cr.row);
        this.challengerTime = cr.ChallengerTime;
        this.defenderTime = cr.DefenderTime;
        @map = ttg.GetMap(xy.x, xy.y);
        this.mapName = ColoredString(map['Name']);
        this.trackId = map['TrackID'];
        this.moveNumber = moveNumber;
        msg = tostring(this.moveNumber) + ". ";
        cName = ttg.GetLeadersName(Challenger);
        dName = ttg.GetLeadersName(Defender);
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
    }

    const string get_SquareCoordStr() const {
        return Highlight(TTG_SquareName(xy.x, xy.y));
    }

    void Draw() {
        UI::TextWrapped(this.msg);
    }
}

class TTGGameEvent_StdResult : TTGGameEvent_MapResult {
    TTGGameEvent_StdResult(TicTacGoState@ ttg, TTGGameEventType type, ChallengeResultState@ cr, int moveNumber) {
        super(ttg, type, cr, moveNumber);
        bool cWon = challengerTime < defenderTime;
        string cTime = challengerTime < DNF_TEST ? HighlightWL(cWon, Time::Format(challengerTime)) : HighlightLoss("DNF");
        string dTime = defenderTime < DNF_TEST ? HighlightWL(!cWon, Time::Format(defenderTime)) : HighlightLoss("DNF");
        bool showDelta = challengerTime + defenderTime < DNF_TEST;
        msg += "  " + cName + ": " + cTime + "\n";
        msg += "  " + dName + ": " + dTime;
        if (showDelta)
            msg += "\n  Delta: " + Time::Format(Math::Abs(challengerTime - defenderTime));
    }
}


class TTGGameEvent_TeamsResult : TTGGameEvent_MapResult {
    TTGGameEvent_TeamsResult(TicTacGoState@ ttg, TTGGameEventType type, ChallengeResultState@ cr, int moveNumber) {
        super(ttg, type, cr, moveNumber);
    }

    void Draw() override {
        UI::AlignTextToFramePadding();
        UI::TextWrapped(this.msg);
        if (TtgCollapsingHeader("Show Results##" + cr.id)) {
            UITeamsScoreBoard(cr, true);
        }
    }
}


class TTGGameEvent_BattleResult : TTGGameEvent_MapResult {
    TTGGameEvent_BattleResult(TicTacGoState@ ttg, TTGGameEventType type, ChallengeResultState@ cr, int moveNumber) {
        super(ttg, type, cr, moveNumber);
    }

    void Draw() override {
        UI::AlignTextToFramePadding();
        UI::TextWrapped(this.msg);
        if (TtgCollapsingHeader("Show Results##" + cr.id)) {
            UIBattleModeScoreBoard(cr, true);
        }
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



void UITeamsScoreBoard(ChallengeResultState@ cr, bool alwaysShowScores = false, bool showTeamsPoints = true) {
    auto score = cr.TeamsCurrentScore;
    if (!alwaysShowScores && cr.IsResolved) {
        auto winner = cr.Winner;
        if (winner != TTGSquareState::Unclaimed) {
            // auto winScore = score[winner];
            // auto loseScore = score[-(winner - 1)];
            auto winnerName = cr.teamNames[winner][0];
            UI::Text("Winners: Team " + winnerName);
            if (showTeamsPoints)
                DrawTeamsTotalPointsVs(score);
        }
    } else {
        if (showTeamsPoints)
            DrawTeamsTotalPointsVs(score);
        if (UI::BeginTable("teams-score-list##"+cr.id, 3, UI::TableFlags::SizingStretchProp)) {
            int[] count = {0, 0};
            int maxPlayers = Math::Min(cr.teamUids[0].Length, cr.teamUids[1].Length);
            for (uint i = 0; i < cr.ranking.Length; i++) {
                auto ur = cr.ranking[i];
                count[ur.team]++;
                // seen[ur.name]
                bool didDNF = ur.time >= DNF_TEST;
                string timeText = didDNF ? "DNF" : TimeFormat(ur.time, true, false);
                string pointsText = (didDNF || !showTeamsPoints) ? "" : (count[ur.team] > maxPlayers ? "" : "+" + (cr.totalUids - i));
                DrawTeamsPlayerScoreRow(ur.team, ur.name, timeText, pointsText);
            }
            for (uint t = 0; t < cr.teamUids.Length; t++) {
                for (uint i = 0; i < cr.teamUids[t].Length; i++) {
                    if (!cr.HasResultFor(cr.teamUids[t][i])) {
                        DrawTeamsPlayerScoreRow(TTGSquareState(t), cr.teamNames[t][i]);
                    }
                }
            }
            UI::EndTable();
        }
    }
}

void DrawTeamsTotalPointsVs(const int[] &in score) {
    UI::PushStyleColor(UI::Col::Text, GetLightColorForTeam(TTGSquareState::Player1));
    UI::Text(tostring(score[0]));
    UI::PopStyleColor();
    UI::SameLine();
    UI::Text("vs.");
    UI::SameLine();
    UI::PushStyleColor(UI::Col::Text, GetLightColorForTeam(TTGSquareState::Player2));
    UI::Text(tostring(score[1]));
    UI::PopStyleColor();
}

void DrawTeamsPlayerScoreRow(TTGSquareState team, const string &in name, const string &in timeText = "", const string &in pointsText = "") {
    UI::PushStyleColor(UI::Col::Text, GetLightColorForTeam(team));
    UI::TableNextRow();
    UI::TableNextColumn();
    UI::Text(name);
    UI::TableNextColumn();
    UI::Text(timeText);
    if (pointsText.Length > 0) {
        UI::TableNextColumn();
        UI::Text(pointsText);
    }
    UI::PopStyleColor();
}

void UIBattleModeScoreBoard(ChallengeResultState@ cr, bool alwaysShowScores = false) {
    auto score = cr.BattleModeCurrentScore;
    auto leader1 = cr.teamNames[0][0];
    auto leader2 = cr.teamNames[1][0];
    if (UI::BeginTable("battle-score-list##"+cr.id, 2, UI::TableFlags::SizingStretchProp)) {
        UI::TableNextRow();
        UI::TableNextColumn();
        UI::PushStyleColor(UI::Col::Text, GetLightColorForTeam(TTGSquareState::Player1));
        UI::Text("Team " + leader1);
        UI::TableNextColumn();
        UI::Text(PointsToStr(score[0]));
        UI::TableNextRow();
        UI::PushStyleColor(UI::Col::Text, GetLightColorForTeam(TTGSquareState::Player2));
        UI::TableNextColumn();
        UI::Text("Team " + leader2);
        UI::TableNextColumn();
        UI::Text(PointsToStr(score[1]));
        UI::PopStyleColor(2);
        UI::EndTable();
    }
    UI::Separator();
    UITeamsScoreBoard(cr, alwaysShowScores, false);
}

const string PointsToStr(int points) {
    return tostring(points) + (points == 1 ? " point" : " points");
}

/**
 * bar along top of screen.
 *      [team p1.........]           |   [.................team p2]
 * midpoint is win
 */
void RenderBattleModeScoreBoard(ChallengeResultState@ cr) {
    // if (cr.ranking.Length == 0) return;
    nvg::Reset();
    vec2 screen = vec2(Draw::GetWidth(), Draw::GetHeight());
    // top middle
    vec2 posTM = vec2(screen.x/2, UI::IsOverlayShown() ? 24 : 0);
    float teamWidth = screen.y * 16. / 9. * 0.4;
    vec2 posTL = posTM - vec2(teamWidth, 0);
    float barHeight = screen.y * 0.04;

    auto score = cr.BattleModeCurrentScore;

    // draw middle bar
    DrawBattleModeMidBar(posTM, screen.y / 100., barHeight);
    // draw team bars
    DrawBattleModeScoreBar(posTL, teamWidth, barHeight, true, "Team " + cr.teamNames[0][0] + ": " + score[0], GetDarkColorForTeam(TTGSquareState::Player1, 1), float(score[0]) / cr.finishesToWin);
    DrawBattleModeScoreBar(posTM, teamWidth, barHeight, false, "Team " + cr.teamNames[1][0] + ": " + score[1], GetDarkColorForTeam(TTGSquareState::Player2, 1), float(score[1]) / cr.finishesToWin);
}

void DrawBattleModeMidBar(vec2 posTM, float width, float height) {
    nvg::BeginPath();
    nvg::Rect(posTM - vec2(width / 2, 0), vec2(width, height));
    nvg::FillColor(vec4(0, 0, 0, 1));
    nvg::Fill();
    nvg::ClosePath();
}

// draw bar for a team on the left or the right
void DrawBattleModeScoreBar(vec2 posTL, float w, float h, bool isLeft, const string &in label, vec4 col, float pctDone) {
    bool noScore = pctDone < 0.001;
    if (!noScore) {
        nvg::BeginPath();
        vec2 size = vec2(w * pctDone, h);
        vec2 posOffs = isLeft ? vec2() : vec2(w * (1 - pctDone), 0);
        nvg::Rect(posTL + posOffs, size);
        nvg::FillColor(col);
        nvg::Fill();
        nvg::ClosePath();
    }
    nvg::FontFace(nvgFontMessage);
    nvg::FontSize(h / 2.);
    nvg::FillColor(noScore ? col : vec4(1, 1, 1, 1));
    nvg::TextAlign(nvg::Align::Middle | (isLeft ? nvg::Align::Left : nvg::Align::Right));
    // vec2 textSize = nvg::TextBounds(label);
    vec2 textOffset = isLeft ? vec2(h / 4., 0) : vec2(w - h / 4., 0);
    vec2 posML = posTL + vec2(0, h/2.);
    nvg::Text(posML + textOffset, label);
}


void RenderTeamsScoreBoard(ChallengeResultState@ cr) {
    // if (cr.ranking.Length == 0) return;
    nvg::Reset();
    vec2 screen = vec2(Draw::GetWidth(), Draw::GetHeight());
    vec2 pos = screen / 2. - vec2(screen.y / 2. * 1.5, screen.y / 4.);
    pos.x = Math::Max(pos.x, 0);
    float elHeight = screen.y / 32.;
    vec2 size = vec2(screen.y / 4., cr.ranking.Length * elHeight);
    vec2 elSize = vec2(size.x, elHeight);
    // background
    nvg::BeginPath();
    nvg::Rect(pos, size);
    nvg::FillColor(vec4(0, 0, 0, .2));
    nvg::Fill();
    nvg::ClosePath();
    // players
    auto fs = elSize.y * 0.4;
    nvg::FontFace(nvgFontMessage);
    nvg::FontSize(fs);
    nvg::TextAlign(nvg::Align::Top | nvg::Align::Left);
    // nvg::FillColor(vec4(1, 1, 1, 1));
    vec2 elPos = pos;
    int[] count = {0, 0};
    if (cr is null || cr.teamUids is null) return;
    int maxPlayers = Math::Min(cr.teamUids[0].Length, cr.teamUids[1].Length);
    int nRanked = cr.ranking.Length;

    auto score = cr.TeamsCurrentScore;
    DrawTeamsScoreOverview(elPos, elSize, score[0], score[1]);
    elPos.y += elHeight;

    for (int i = 0; i < nRanked; i++) {
        auto ur = cr.ranking[i];
        count[ur.team]++;
        DrawTeamsPlayerScoreEntry(ur.team, ur.name, ur.time, elPos, elSize, i, cr.totalUids, count[ur.team] > maxPlayers);
        elPos.y += elHeight;
    }
    for (uint t = 0; t < cr.teamUids.Length; t++) {
        for (uint i = 0; i < cr.teamUids[t].Length; i++) {
            if (!cr.HasResultFor(cr.teamUids[t][i])) {
                DrawTeamsPlayerScoreEntry(TTGSquareState(t), cr.teamNames[t][i], -1, elPos, elSize, cr.totalUids, cr.totalUids, true);
                elPos.y += elHeight;
            }
        }
    }
}

void DrawTeamsPlayerScoreEntry(TTGSquareState team, const string &in name, int time, vec2 elPos, vec2 elSize, int i, int nPlayers, bool noPoints) {
    vec4 bgCol = GetDarkColorForTeam(team);
    nvg::BeginPath();
    nvg::Rect(elPos, elSize);
    nvg::FillColor(bgCol);
    nvg::Fill();
    nvg::ClosePath();

    // 5% padding
    auto pad = elSize * vec2(0.05, 0.3);
    auto timeOffs = elSize * vec2(.6, 0);
    auto pointsOff = elSize * vec2(.86, 0);
    nvg::FillColor(vec4(1, 1, 1, 1));
    bool didDNF = time >= DNF_TEST;
    string timeText = time < 0 ? "" : (didDNF ? "DNF" : TimeFormat(time, true, false));
    nvg::Text(elPos + pad, name);
    nvg::Text(elPos + pad + timeOffs, timeText);
    nvg::Text(elPos + pad + pointsOff, (didDNF || noPoints) ? "" : "+" + (nPlayers - i));
}

void DrawTeamsScoreOverview(vec2 elPos, vec2 elSize, int pointsLeft, int pointsRight) {
    float leftWidth = elSize.x * 0.475;
    if ((pointsLeft + pointsRight) != 0) {
        leftWidth = 0.95 * (float(pointsLeft) / float(pointsLeft + pointsRight));
        leftWidth = Math::Min(0.8, Math::Max(leftWidth, 0.2));
        leftWidth *= elSize.x;
    }
    float rightWidth = elSize.x * 0.95 - leftWidth;
    vec2 leftSize = vec2(leftWidth, elSize.y);
    vec2 rightPos = vec2(elPos.x + (elSize.x - rightWidth), elPos.y);
    vec2 rightSize = vec2(rightWidth, elSize.y);
    auto leftCol = GetDarkColorForTeam(TTGSquareState::Player1);
    auto rightCol = GetDarkColorForTeam(TTGSquareState::Player2);

    nvg::BeginPath();
    nvg::Rect(elPos, leftSize);
    nvg::FillColor(leftCol);
    nvg::Fill();
    nvg::ClosePath();

    nvg::BeginPath();
    nvg::Rect(rightPos, rightSize);
    nvg::FillColor(rightCol);
    nvg::Fill();
    nvg::ClosePath();

    auto pad = elSize * vec2(0.05, 0.3);
    // auto timeOffs = elSize * vec2(.6, 0);
    // auto pointsOff = elSize * vec2(.86, 0);

    nvg::FillColor(vec4(1, 1, 1, 1));
    nvg::Text(elPos + pad, tostring(pointsLeft));

    string pointsText = tostring(pointsRight);
    auto textWidth = nvg::TextBounds(pointsText);
    nvg::Text(rightPos + vec2(rightSize.x - textWidth.x - pad.x, pad.y), pointsText);
}

vec4 GetDarkColorForTeam(TTGSquareState team, float alpha = .75) {
    if (team == TTGSquareState::Player1) return vec4(0, 0, .5, alpha);
    if (team == TTGSquareState::Player2) return vec4(.5, 0, 0, alpha);
    return vec4(0, .5, 0, alpha);
}

vec4 GetLightColorForTeam(TTGSquareState team) {
    // return GetDarkColorForTeam(team) + vec4(.5, .5, .5, .25);
    if (team == TTGSquareState::Player1) return vec4(0.189f, 0.628f, 0.958f, 1.000f);
    if (team == TTGSquareState::Player2) return vec4(0.942f, 0.413f, 0.400f, 1.000f);
    return vec4(0.610f, 0.961f, 0.590f, 1.000f);
}

const string TTG_SquareName(int col, int row) {
    auto rowStr = tostring(row + 1);
    if (col == 0) {
        return "A" + rowStr;
    } else if (col == 1) {
        return "B" + rowStr;
    } else if (col == 2) {
        return "C" + rowStr;
    }
    warn("unknown coord square name: " + col + ", " + row);
    return "" + (col + 1) + "," + rowStr;
}
