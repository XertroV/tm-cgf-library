/**
 * Single Player: for demo / testing
 * Standard: 1v1
 * Teams: N v N (or w/e) with ranked points scoring system
 * BattleMode:
 */

enum TTGMode {
    SinglePlayer = 1,
    Standard = 2,
    Teams = 6,
    BattleMode = 64
}

class SquareState {
    bool seen;
    TTGSquareState owner = TTGSquareState::Unclaimed;

    SquareState() {
        Reset();
    }

    void Reset() {
        seen = false;
        owner = TTGSquareState::Unclaimed;
    }

    bool get_IsUnclaimed() const {
        return IsOwnedBy(TTGSquareState::Unclaimed);
    }

    bool IsOwnedBy(TTGSquareState player) const {
        return owner == player;
    }
}

class TicTacGoState {
    Game::Client@ client;

    TTGMode mode = TTGMode::Standard;
    TTGGameState state = TTGGameState::PreStart;

    SquareState[][] boardState;
    // bool[][] boardMapKnown;

    TTGSquareState MyTeamLeader = TTGSquareState::Unclaimed;
    TTGSquareState TheirTeamLeader = TTGSquareState::Unclaimed;
    bool IAmALeader = false;
    TTGSquareState ActiveLeader = TTGSquareState::Unclaimed;
    TTGSquareState WinningLeader = TTGSquareState::Unclaimed;
    int2[] WinningSquares;

    string MyLeadersName;
    string OpposingLeaderName;

    ChallengeResultState@ challengeResult = ChallengeResultState();
    TTGGameEvent@[] gameLog;
    uint turnCounter = 0;

    bool opt_EnableRecords = false;

    TicTacGoState(Game::Client@ client) {
        @this.client = client;
        Reset();
    }

    void Reset() {
        mode = TTGMode::Standard;
        state = TTGGameState::PreStart;
        turnCounter = 0;
        gameLog.Resize(0);
        challengeResult.Reset();
        ActiveLeader = TTGSquareState::Unclaimed;
        MyTeamLeader = TTGSquareState::Unclaimed;
        TheirTeamLeader = TTGSquareState::Unclaimed;
        WinningLeader = TTGSquareState::Unclaimed;

        boardState.Resize(3);
        for (uint i = 0; i < 3; i++) {
            boardState[i].Resize(3);
            for (uint j = 0; j < 3; j++) {
                boardState[i][j].Reset();
            }
        }
    }

    void OnGameStart() {
        InitGameOnStart();
        state = TTGGameState::WaitingForMove;
    }

    void OnGameEnd() {
        state = TTGGameState::GameFinished;
    }

    void LoadFromGameOpts(const Json::Value@ game_opts) {
        Reset();
        if (game_opts.GetType() != Json::Type::Object) {
            log_warn("LoadFromGameOpts: game_opts is not a json object");
            return;
        }
        opt_EnableRecords = GetGameOptBool(game_opts, 'enable_records', false);
        // mode = GetGameOptMode(game_opts);
        mode = TTGMode(GetGameOptInt(game_opts, 'mode', int(TTGMode::Standard)));
        warn("Set mode to: " + tostring(mode));
    }

    GameInfoFull@ get_GameInfo() {
        return client.gameInfoFull;
    }

    bool UidInTeam(const string &in uid, int team) {
        auto teamUids = GameInfo.teams[team];
        for (uint i = 0; i < teamUids.Length; i++) {
            if (uid == teamUids[i]) return true;
        }
        return false;
    }

    TTGSquareState UidToLeader(const string &in uid) {
        if (GameInfo.teams[0][0] == uid) return TTGSquareState::Player1;
        if (IsSinglePlayer) return TTGSquareState::Player1;
        if (GameInfo.teams[1][0] == uid) return TTGSquareState::Player2;
        return TTGSquareState::Unclaimed;
    }

    TTGSquareState UidToTeam(const string &in uid) {
        if (UidInTeam(uid, 0)) return TTGSquareState::Player1;
        if (UidInTeam(uid, 1)) return TTGSquareState::Player2;
        return TTGSquareState::Unclaimed;
    }

    const string[][]@ get_TeamUids() {
        return GameInfo.teams;
    }



    void InitGameOnStart() {
        while (GameInfo is null) {
            log_trace("InitGameOnStart found null game info, yielding");
            yield();
        }
        LoadFromGameOpts(GameInfo.game_opts);
        ActiveLeader = TTGSquareState(GameInfo.team_order[0]);
        string myUid = client.clientUid;
        bool onTeam1 = UidInTeam(myUid, 0);
        // bool isPlayer1 = GameInfo.teams[0][0] == myUid;
        string myLeaderUid = IsSinglePlayer ? myUid : GameInfo.teams[onTeam1 ? 0 : 1][0];
        string oppUid = IsSinglePlayer ? myUid : GameInfo.teams[onTeam1 ? 1 : 0][0];
        if (onTeam1) {
            MyTeamLeader = TTGSquareState::Player1;
            TheirTeamLeader = TTGSquareState::Player2;
        } else {
            MyTeamLeader = TTGSquareState::Player2;
            TheirTeamLeader = TTGSquareState::Player1;
        }
        print("ActivePlayer (start): " + tostring(ActiveLeader));
        // setPlayersRes = "Active=" + tostring(ActivePlayer) + "; " + "MyTeamLeader=" + tostring(MyTeamLeader);
        for (uint i = 0; i < GameInfo.players.Length; i++) {
            auto item = GameInfo.players[i];
            if (item.uid == oppUid) {
                OpposingLeaderName = item.username;
            }
            if (item.uid == myLeaderUid) {
                MyLeadersName = item.username;
            }
        }
        if (OpposingLeaderName == "??") {
            warn("Could not find opponents name.");
        }
        gameLog.InsertLast(TTGGameEvent_StartingPlayer(ActiveLeader, ActiveLeadersName));
    }


    TTGSquareState get_InactiveLeader() const {
        return ActiveLeader == TTGSquareState::Player1 ? TTGSquareState::Player2 : TTGSquareState::Player1;
    }

    const string get_ActiveLeadersName() const {
        return ActiveLeader == MyTeamLeader ? MyLeadersName : OpposingLeaderName;
    }

    const string GetLeadersName(TTGSquareState l) const {
        return l == MyTeamLeader ? MyLeadersName : OpposingLeaderName;
    }

    bool get_IsSinglePlayer() const {
        return mode == TTGMode::SinglePlayer;
    }

    bool get_IsStandard() const {
        return mode == TTGMode::Standard;
    }

    bool get_IsTeams() const {
        return mode == TTGMode::Teams;
    }

    bool get_IsBattleMode() const {
        return mode == TTGMode::BattleMode;
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





    SquareState@ GetSquareState(int col, int row) {
        // trace_dev("xy: " + col + ", " + row);
        return boardState[col][row];
    }

    void SetSquareState(int col, int row, TTGSquareState s) {
        GetSquareState(col, row).owner = s;
    }

    void MarkSquareKnown(int col, int row) {
        boardState[col][row].seen = true;
    }

    bool SquareKnown(int col, int row) {
        return boardState[col][row].seen;
    }

    bool SquareOwnedByMe(int col, int row) const {
        return boardState[col][row].IsOwnedBy(MyTeamLeader);
    }

    bool SquareOwnedByThem(int col, int row) const {
        return boardState[col][row].IsOwnedBy(TheirTeamLeader);
    }



    bool get_IsMyTurn() {
        return MyTeamLeader == ActiveLeader || IsSinglePlayer;
    }

    bool SquarePartOfWin(int2 xy) {
        for (uint i = 0; i < WinningSquares.Length; i++) {
            auto s = WinningSquares[i];
            if (xy.x == s.x && xy.y == s.y) return true;
        }
        return false;
    }




    void AdvancePlayerTurns() {
        // todo: check for win
        if (CheckGameWon()) return;
        // else, update active player
        // ActivePlayer = ActivePlayer == MyTeamLeader ? TheirTeamLeader : MyTeamLeader;
        ActiveLeader = InactiveLeader;
        turnCounter++;
    }

    // check if 3 squares are claimed and equal
    bool AreSquaresEqual(int2 a, int2 b, int2 c) {
        auto _a = GetSquareState(a.x, a.y).owner;
        auto _b = GetSquareState(b.x, b.y).owner;
        bool win = _a != TTGSquareState::Unclaimed
            && _a == _b
            && _b == GetSquareState(c.x, c.y).owner;
        if (win) WinningLeader = _a;
        WinningSquares.Resize(0);
        WinningSquares.InsertLast(a);
        WinningSquares.InsertLast(b);
        WinningSquares.InsertLast(c);
        return win;
    }

    bool CheckGameWon() {
        bool gameWon = IsGameFinished
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




    bool IsValidMove(const string &in msgType, uint col, uint row, TTGSquareState fromPlayer, bool isFromLeader, const string &in lastFromUid) const {
        if (fromPlayer == TTGSquareState::Unclaimed) return false;
        if (IsGameFinished) return false;
        if (IsInChallenge || IsInClaim) {
            bool moveIsChallengeRes = msgType == "G_CHALLENGE_RESULT";
            if (!moveIsChallengeRes) return false;
            if (IsSinglePlayer && challengeResult.HasResultFor(fromPlayer)) return false;
            if (!IsSinglePlayer && challengeResult.HasResultFor(lastFromUid)) return false;
            return true;
        } else if (IsWaitingForMove) {
            if (col >= 3 || row >= 3) return false;
            if (!isFromLeader) return false;
            if (fromPlayer != ActiveLeader && !IsSinglePlayer) return false;
            bool moveIsClaiming = msgType == "G_TAKE_SQUARE";
            bool moveIsChallenging = msgType == "G_CHALLENGE_SQUARE";
            if (!moveIsChallenging && !moveIsClaiming) return false;
            if (moveIsChallenging) {
                auto sqState = GetSquareState(col, row);
                if (sqState.IsUnclaimed) return false;
                return !sqState.IsOwnedBy(fromPlayer) || IsSinglePlayer;
            } else if (moveIsClaiming) {
                print('test move claiming');
                return GetSquareState(col, row).IsUnclaimed;
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
        auto lastFromUid = string(msg['from']['uid']);
        auto lastFromUsername = string(msg['from']['username']);
        auto lastFromLeader = UidToLeader(lastFromUid);
        auto lastFromTeam = UidToTeam(lastFromUid);
        bool fromALeader = lastFromLeader != TTGSquareState::Unclaimed;
        // check if valid move
        // todo: lastfrom
        if (!IsValidMove(msgType, col, row, lastFromTeam, fromALeader, lastFromUid)) {
            warn("Invalid move from " + lastFromUsername + ": " + Json::Write(JsonObject2("type", msgType, "payload", pl)));
            return;
        }

        trace("Processing valid move of type: " + msgType + "; " + Json::Write(pl));

        // proceed with state mutation

        if (IsInChallenge || IsInClaim) {
            bool moveIsChallengeRes = msgType == "G_CHALLENGE_RESULT";
            if (!moveIsChallengeRes) throw("!moveIsChallengeRes: should be impossible");
            if (!challengeResult.active) throw("challenge is not active");
            if (!IsSinglePlayer) {
                challengeResult.SetPlayersTime(lastFromUid, int(pl['time']), lastFromTeam);
            } else {
                // if we're in a single player game, set a slightly worse time for the inactive player
                challengeResult.SetPlayersTime(ActiveLeader, int(pl['time']));
                challengeResult.SetPlayersTime(InactiveLeader, int(pl['time']) + 100);
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
            if (lastFromLeader != ActiveLeader && !IsSinglePlayer) throw("impossible: lastFrom != ActiveLeader");
            bool moveIsClaiming = msgType == "G_TAKE_SQUARE";
            bool moveIsChallenging = msgType == "G_CHALLENGE_SQUARE";
            if (!moveIsChallenging && !moveIsClaiming) throw("impossible: not a valid move");
            auto sqState = GetSquareState(col, row);
            if (moveIsChallenging) {
                if (sqState.IsUnclaimed) throw('invalid, square claimed');
                if (sqState.IsOwnedBy(ActiveLeader)) throw('invalid, cant challenge self');
                // begin challenge
                state = TTGGameState::InChallenge;
                challengeResult.Activate(col, row, ActiveLeader, state, TeamUids, mode);
                startnew(CoroutineFunc(BeginChallengeSoon));
            } else if (moveIsClaiming) {
                if (!sqState.IsUnclaimed) throw("claiming claimed square");
                state = TTGGameState::InClaim;
                challengeResult.Activate(col, row, ActiveLeader, state, TeamUids, mode);
                startnew(CoroutineFunc(BeginChallengeSoon));
                // SetSquareState(col, row, ActiveLeader);
                // AdvancePlayerTurns();
            }
            MarkSquareKnown(col, row);
        }
    }


    // challenges and maps


    Json::Value@ currMap;
    int currTrackId;
    string currTrackIdStr;

    int challengePreWaitPeriod = 3000;

    void BeginChallengeSoon() {
        auto col = challengeResult.col;
        auto row = challengeResult.row;
        auto map = GetMap(col, row);
        @currMap = map;
        currTrackId = map['TrackID'];
        currTrackIdStr = tostring(currTrackId);
        challengeResult.startTime = Time::Now + challengePreWaitPeriod;
        // autostart if not
        if (!IsSinglePlayer) {
            sleep(challengePreWaitPeriod);
            // load map immediately
        }
    }

    Json::Value@ GetMap(int col, int row) {
        int mapIx = row * 3 + col;
        if (mapIx >= client.mapsList.Length) throw('bad map index');
        return client.mapsList[mapIx];
    }




    // relative to Time::Now to avoid pause menu strats
    int challengeStartTime = -1;
    int challengeEndTime = -1;
    int challengeScreenTimeout = -1;
    int currGameTime = -1;
    int currPeriod = 15;  // frame time
    bool challengeRunActive = false;
    bool disableLaunchMapBtn = false;
    uint challengeEndedAt;

    void RunChallengeAndReportResult() {
        disableLaunchMapBtn = true;
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
            auto oppTime = challengeResult.GetResultFor(TheirTeamLeader, DNF_TIME);
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
        // ! note: we could use better methods for calculating duration (MLFeed is an example), but the goal here is something simple, reasonably robust, and *light*. Dependancies can be added per-plugin based on that game's requirements. We don't really need that sort of accuracy here.
        challengeEndTime += currPeriod;
        duration = challengeEndTime - challengeStartTime;
        // report result
        ReportChallengeResult(duration);
        sleep(3000);
        EndChallenge();
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

}




bool GetGameOptBool(const Json::Value@ opts, const string &in key, bool def) {
    try {
        return string(opts[key]).ToLower() == "true";
    } catch {
        return def;
    }
}



int GetGameOptInt(const Json::Value@ opts, const string &in key, int def) {
    try {
        return Text::ParseInt(opts[key]);
    } catch {
        return def;
    }
}
