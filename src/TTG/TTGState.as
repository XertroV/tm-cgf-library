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
    int2 lastColRow = int2(-1, -1);
    // bool[][] boardMapKnown;

    TTGSquareState MyTeamLeader = TTGSquareState::Unclaimed;
    TTGSquareState TheirTeamLeader = TTGSquareState::Unclaimed;
    bool IAmALeader = false;
    TTGSquareState ActiveLeader = TTGSquareState::Unclaimed;
    TTGSquareState WinningLeader = TTGSquareState::Unclaimed;
    int2[] WinningSquares;

    string MyName;
    string MyLeadersName;
    string OpposingLeaderName;

    ChallengeResultState@ challengeResult = ChallengeResultState();
    TTGGameEvent@[] gameLog;
    uint turnCounter = 0;
    protected string[][] teamNames;

    bool opt_EnableRecords = false;
    bool opt_FirstRoundForCenter = false;
    bool opt_CannotImmediatelyRepick = false;
    bool opt_RevealMaps = false;
    int opt_AutoDNF = -1;
    // used during battle mode
    int opt_FinishesToWin = 1;

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
        teamNames.Resize(0);
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
        opt_AutoDNF = GetGameOptInt(game_opts, 'auto_dnf', -1);
        opt_RevealMaps = GetGameOptBool(game_opts, 'reveal_maps', false);
        mode = TTGMode(GetGameOptInt(game_opts, 'mode', int(TTGMode::Standard)));
        warn("Set mode to: " + tostring(mode));
        // mode = GetGameOptMode(game_opts);
        if (IsBattleMode) opt_FinishesToWin = GetGameOptInt(game_opts, 'finishes_to_win', 1);

        opt_FirstRoundForCenter = GetGameOptBool(game_opts, '1st_round_for_center', false);
        opt_CannotImmediatelyRepick = GetGameOptBool(game_opts, 'cannot_repick', false);

        if (IsSinglePlayer) opt_FirstRoundForCenter = false;
    }

    int get_opt_AutoDNF_ms() {
        return opt_AutoDNF * 1000;
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

    const string[][]@ get_TeamNames() {
        if (teamNames.Length == 0 && TeamUids.Length != 0) {
            teamNames.Resize(TeamUids.Length);
            for (uint i = 0; i < TeamUids.Length; i++) {
                auto @team = TeamUids[i];
                teamNames[i].Resize(team.Length);
                for (uint p = 0; p < team.Length; p++) {
                    auto u = GetGameInfoUser(team[p]);
                    teamNames[i][p] = u is null ? "? Unk" : u.username;
                }
            }
        }
        return teamNames;
    }

    const User@ GetGameInfoUser(const string &in uid) {
        for (uint i = 0; i < GameInfo.players.Length; i++) {
            User@ item = GameInfo.players[i];
            if (uid == item.uid) return item;
        }
        return null;
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
        IAmALeader = myUid == myLeaderUid;
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
            User@ item = GameInfo.players[i];
            if (item.uid == oppUid) {
                OpposingLeaderName = item.username;
            }
            if (item.uid == myLeaderUid) {
                MyLeadersName = item.username;
            }
            if (item.uid == client.clientUid) {
                MyName = item.username;
            }
        }
        if (OpposingLeaderName == "??") {
            warn("Could not find opponents name.");
        }
        gameLog.InsertLast(TTGGameEvent_StartingPlayer(ActiveLeader, ActiveLeadersName));
        // call this to autogen the lists at game start, which is more convenient than on-demand
        auto tmp = TeamNames;

        if (opt_RevealMaps) {
            for (int col = 0; col < 3; col++) {
                for (int row = 0; row < 3; row++) {
                    MarkSquareKnown(col, row);
                }
            }
        }

        state = TTGGameState::WaitingForMove;
        if (opt_FirstRoundForCenter) {
            @gameLog[0] = TTGGameEvent_StartingForCenter();
            state = TTGGameState::InClaim;
            MarkSquareKnown(1, 1);
            challengeResult.Activate(1, 1, TTGSquareState::Unclaimed, state, TeamUids, TeamNames, mode, opt_FinishesToWin);
            startnew(CoroutineFunc(BeginChallengeSoon));
        }
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
        auto team = !IsSinglePlayer ? MyTeamLeader : ActiveLeader;
        return boardState[col][row].IsOwnedBy(team);
    }

    bool SquareOwnedByThem(int col, int row) const {
        auto team = !IsSinglePlayer ? TheirTeamLeader : InactiveLeader;
        return boardState[col][row].IsOwnedBy(team);
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

    bool WasPriorSquare(int col, int row) {
        return lastColRow.x == col && lastColRow.y == row;
    }




    bool IsValidMove(const string &in msgType, uint col, uint row, TTGSquareState fromPlayer, bool isFromLeader, const string &in lastFromUid) const {
        if (fromPlayer == TTGSquareState::Unclaimed) return false;
        if (IsGameFinished) return false;
        if (IsInChallenge || IsInClaim) {
            bool moveIsChallengeRes = msgType == "G_CHALLENGE_RESULT";
            bool moveIsForceEnd = msgType == "G_CHALLENGE_FORCE_END";
            if (!moveIsChallengeRes && !moveIsForceEnd) return false;
            if (moveIsForceEnd) {
                return client.IsPlayerAdminOrMod(lastFromUid);
            }
            if (IsSinglePlayer && challengeResult.HasResultFor(fromPlayer)) return false;
            if (!IsSinglePlayer && challengeResult.HasResultFor(lastFromUid)) return false;
            return true;
        } else if (IsWaitingForMove) {
            if (col >= 3 || row >= 3) return false;
            if (!isFromLeader) return false;
            if (fromPlayer != ActiveLeader && !IsSinglePlayer) return false;
            if (opt_CannotImmediatelyRepick && WasPriorSquare(col, row)) return false;
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
        bool isReplay = seq < client.GameReplayNbMsgs;
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
            bool moveIsForceEnd = msgType == "G_CHALLENGE_FORCE_END";
            if (!moveIsChallengeRes && !moveIsForceEnd) throw("not a valid move type: should be impossible");
            if (!challengeResult.active) throw("challenge is not active");
            if (moveIsForceEnd) {
                if (!client.IsPlayerAdminOrMod(lastFromUid)) throw("force end from a non admin/mod");
                challengeResult.ForceEnd();
                gameLog.InsertLast(TTGGameEvent_ForceEnd(lastFromUsername, lastFromUid));
                if (!challengeResult.IsResolved)
                    warn("we just force ended the challenge but it did not resolve!");
            } else if (IsSinglePlayer) {
                // if we're in a single player game, set a slightly worse time for the inactive player
                challengeResult.SetPlayersTime(ActiveLeader, int(pl['time']));
                challengeResult.SetPlayersTime(InactiveLeader, int(pl['time']) + 100);
            } else {
                challengeResult.SetPlayersTime(lastFromUid, lastFromUsername, int(pl['time']), lastFromTeam);
            }
            if (challengeResult.IsResolved) {
                bool challengerWon = challengeResult.Winner == challengeResult.challenger;
                if (opt_FirstRoundForCenter && turnCounter == 0) {
                    warn('setting winner: ' + tostring(challengeResult.Winner));
                    challengerWon = challengeResult.Winner != TTGSquareState::Unclaimed;
                    if (challengerWon) {
                        challengeResult.challenger = challengeResult.Winner;
                        ActiveLeader = challengeResult.challenger;
                    } else {
                        challengeResult.challenger = ActiveLeader;
                    }
                    challengeResult.defender = TTGSquareState(-(challengeResult.challenger - 1));
                    print('challengeResult.challenger: ' + tostring(challengeResult.challenger));
                    print('challengeResult.defender: ' + tostring(challengeResult.defender));
                }
                auto eType = TTGGameEventType((IsInChallenge ? 4 : 2) | (challengerWon ? 1 : 0));
                gameLog.InsertLast(TTGGameEvent_ResultForMode(this, eType, challengeResult, turnCounter + 1));

                bool claimFailed = IsInClaim && !challengerWon;
                auto sqState = claimFailed ? TTGSquareState::Unclaimed : challengeResult.Winner;
                int2 xy = int2(challengeResult.col, challengeResult.row);
                SetSquareState(xy.x, xy.y, sqState);
                if (opt_CannotImmediatelyRepick) {
                    lastColRow = challengerWon ? xy : int2(-1, -1);
                }

                challengeResult.Reset();
                challengeEndedAt = Time::Now;

                state = TTGGameState::WaitingForMove;
                AdvancePlayerTurns();
            }
        } else if (IsWaitingForMove) {
            if (col >= 3 || row >= 3) throw("impossible: col >= 3 || row >= 3");
            if (col < 0 || row < 0) throw("impossible: col < 0 || row < 0");
            if (lastFromLeader != ActiveLeader && !IsSinglePlayer) throw("impossible: lastFrom != ActiveLeader");
            if (opt_CannotImmediatelyRepick && WasPriorSquare(col, row)) throw("cannot repick");
            bool moveIsClaiming = msgType == "G_TAKE_SQUARE";
            bool moveIsChallenging = msgType == "G_CHALLENGE_SQUARE";
            if (!moveIsChallenging && !moveIsClaiming) throw("impossible: not a valid move");
            auto sqState = GetSquareState(col, row);
            auto finishesToWin = IsBattleMode ? opt_FinishesToWin : 1;
            @challengeResult = ChallengeResultState();
            if (moveIsChallenging) {
                if (sqState.IsUnclaimed) throw('invalid, square claimed');
                if (sqState.IsOwnedBy(ActiveLeader)) throw('invalid, cant challenge self');
                // begin challenge
                state = TTGGameState::InChallenge;
                challengeResult.Activate(col, row, ActiveLeader, state, TeamUids, TeamNames, mode, finishesToWin);
                startnew(CoroutineFunc(BeginChallengeSoon));
            } else if (moveIsClaiming) {
                if (!sqState.IsUnclaimed) throw("claiming claimed square");
                state = TTGGameState::InClaim;
                challengeResult.Activate(col, row, ActiveLeader, state, TeamUids, TeamNames, mode, finishesToWin);
                startnew(CoroutineFunc(BeginChallengeSoon));
            }
            MarkSquareKnown(col, row);
        }
    }


    // challenges and maps


    Json::Value@ currMap;
    int currTrackId;
    string currTrackIdStr;

    int challengePreWaitPeriod = 3000;
    string beginChallengeLatestNonce;

    void BeginChallengeSoon() {
        // this can happen when replaying game events
        if (!challengeResult.active) return;
        if (!IsInClaimOrChallenge) return;
        string myNonce = Crypto::RandomBase64(10);
        beginChallengeLatestNonce = myNonce;
        auto col = challengeResult.col;
        auto row = challengeResult.row;
        auto map = GetMap(col, row);
        @currMap = map;
        currTrackId = map['TrackID'];
        currTrackIdStr = tostring(currTrackId);
        challengeResult.startTime = Time::Now + challengePreWaitPeriod;
        // autostart if not
        if (!IsSinglePlayer && !S_LocalDev) {
            // we sleep for slightly less to avoid race conditions with the launch map button
            sleep(challengePreWaitPeriod - 30);
            // load map immediately if the CR is the same one and the setting is enabled.
            bool crChecks = beginChallengeLatestNonce == myNonce && !challengeResult.HasResultFor(client.clientUid);
            if (crChecks && !challengeRunActive && S_TTG_AutostartMap && !CurrentlyInMap) {
                print("Autostarting map for: " + MyName);
                startnew(CoroutineFunc(RunChallengeAndReportResult));
            }
        }
    }

    Json::Value@ GetMap(int col, int row) {
        int mapIx = row * 3 + col;
        if (mapIx >= int(client.mapsList.Length)) throw('bad map index');
        if (mapIx < 0) throw('negavive col/row?: ' + col + ", " + row);
        return client.mapsList[mapIx];
    }



    void ResetLaunchMapBtnIn3s() {
        sleep(3000);
        disableLaunchMapBtn = false;
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
    bool showForceEndPrompt = false;
    bool shouldExitChallenge = false;
    uint shouldExitChallengeTime = DNF_TIME;

    void RunChallengeAndReportResult() {
        showForceEndPrompt = false;
        shouldExitChallenge = false;
        disableLaunchMapBtn = true;
        challengeStartTime = -1;
        currGameTime = -1;
        currPeriod = 15;
        // join map
        challengeRunActive = true;
        LoadMapNow(MapUrl(currMap));
        startnew(CoroutineFunc(ResetLaunchMapBtnIn3s));
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
        yield(); // we don't need to get the time immediately, so give some time for values to update
        while (player.StartTime < 0) yield();
        HideGameUI::opt_EnableRecords = opt_EnableRecords;
        startnew(HideGameUI::OnMapLoad);
        yield();
        yield();
        // start of challenge
        currGameTime = GetApp().PlaygroundScript.Now;
        // ! timer bugs sometimes on start hmm
        challengeStartTime = Time::Now + (player.StartTime - currGameTime);
        if (challengeStartTime < Time::Now) {
            warn("challengeStartTime is in the past; now - start = " + (int(Time::Now) - challengeStartTime) + ". setting to 1.5s in the future.");
            // the timer should always start at -1.5s, so set it 1.5s in the future
            challengeStartTime = Time::Now + 1500;
        }

        log_info("Set challenge start time: " + challengeStartTime);
        // wait for finish timer
        int duration;
        while (uiConfig is null || uiConfig.UISequence != CGamePlaygroundUIConfig::EUISequence::Finish) {
            duration = Time::Now - challengeStartTime;
            auto oppTime = challengeResult.ranking.Length > 0 ? challengeResult.ranking[0].time : DNF_TIME;
            auto timeLeft = oppTime + opt_AutoDNF_ms - duration;
            bool shouldDnf = opt_AutoDNF_ms > 0 && timeLeft <= 0;
            // if the challenge is resolved (e.g., via force ending) then we want to exit out
            // also if we already have a result
            shouldExitChallenge = challengeResult.IsResolved || challengeResult.HasResultFor(client.clientUid);
            if (shouldDnf || shouldExitChallenge || GetApp().PlaygroundScript is null || uiConfig is null) {
                log_trace('should dnf, or exit, or player already did.');
                if (shouldDnf) {
                    log_warn("shouldDnf. time left: " + timeLeft + "; oppTime: " + oppTime + ", duration=" + duration);
                }
                // don't report a time if the challenge is resolved b/c it's an invalid move
                if (!shouldExitChallenge)
                    ReportChallengeResult(DNF_TIME); // more than 24 hrs, just
                // if we are still in the map we want to let hte user know before we exit
                if (shouldExitChallenge) {
                    shouldExitChallengeTime = Time::Now + 3000;
                    AwaitShouldExitTimeOrMapLeft();
                    // sleep(3000);
                }
                // player quit (or auto DNF)
                warn("Map left. Either: player quit, autodnf, or challenge resolved");
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

    // uses shouldExitChallengeTime
    void AwaitShouldExitTimeOrMapLeft() {
        while (shouldExitChallengeTime > Time::Now && CurrentlyInMap) yield();
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

    void SendForceEnd() {
        client.SendPayload("G_CHALLENGE_FORCE_END", JsonObject2("col", challengeResult.col, "row", challengeResult.row));
    }
}




class ChallengeResultState {
    string id = Crypto::RandomBase64(8);
    int player1Time = -1;
    int player2Time = -1;
    bool active = false;
    int row = -1;
    int col = -1;
    int startTime = -1;
    int firstResultAt = -1;
    TTGSquareState challenger = TTGSquareState::Unclaimed;
    TTGSquareState defender = TTGSquareState::Unclaimed;
    TTGGameState challengeType;

    TTGMode mode;
    dictionary uidTimes;
    string[][]@ teamUids;
    string[][]@ teamNames;
    int totalUids = -1;
    UidRank@[] ranking;
    int finishesToWin = 1;

    void Reset() {
        startTime = -1;
        active = false;
    }

    void Activate(uint col, uint row, TTGSquareState challenger, TTGGameState type, string[][] &in teamUids, string[][] &in teamNames, TTGMode mode, int battle_finishesToWin) {
        if (active) throw("already active");
        this.col = int(col);
        this.row = int(row);
        active = true;
        player1Time = -1;
        player2Time = -1;
        uidTimes.DeleteAll();
        this.challenger = challenger;
        this.defender = challenger == TTGSquareState::Unclaimed ? TTGSquareState::Unclaimed
            : TTGSquareState(-(challenger - 1));
        challengeType = type;
        @this.teamNames = teamNames;
        @this.teamUids = teamUids;
        totalUids = teamUids[0].Length + (teamUids.Length == 1 ? 0 : teamUids[1].Length);
        this.mode = mode;
        ranking.Resize(0);
        firstResultAt = -1;
        this.finishesToWin = battle_finishesToWin;
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
        return ResolvedLegacyMethod
            || AllTimesAreSubmitted
            || BattleModeEnoughFinishes;
    }

    bool get_AllTimesAreSubmitted() const {
        return totalUids > 0 && totalUids == int(uidTimes.GetSize());
    }

    bool get_BattleModeEnoughFinishes() const {
        if (mode != TTGMode::BattleMode) return false;
        if (int(uidTimes.GetSize()) < finishesToWin) return false;
        auto score = BattleModeCurrentScore;
        return score[0] >= finishesToWin || score[1] >= finishesToWin;
    }

    bool get_ResolvedLegacyMethod() const {
        return mode == TTGMode::SinglePlayer && player1Time > 0 && player2Time > 0;
    }

    TTGSquareState get_Winner() const {
        if (!IsResolved) return TTGSquareState::Unclaimed;
        if (ResolvedLegacyMethod) return WinnerLegacyMethod;
        if (mode == TTGMode::Standard) return WinnerStandard;
        if (mode == TTGMode::Teams) return WinnerTeams;
        if (mode == TTGMode::BattleMode) return WinnerBattleMode;
        throw("get_Winner, no mode? should never happen");
        return TTGSquareState::Unclaimed;
    }

    TTGSquareState get_WinnerStandard() const {
        int minTime = DNF_TIME;
        TTGSquareState winningTeam = TTGSquareState::Unclaimed;
        for (int i = 0; i < int(teamUids.Length); i++) {
            auto currTeam = TTGSquareState(i);
            auto @team = teamUids[i];
            for (uint j = 0; j < team.Length; j++) {
                string uid = team[j];
                int time = DNF_TIME;
                //if (!uidTimes.Exists(uid)) continue;
                if (!uidTimes.Get(uid, time)) continue;
                if (time < minTime || (currTeam == defender && (time == minTime || minTime > DNF_TEST))) {
                    minTime = time;
                    winningTeam = currTeam;
                }
            }
        }
        if (minTime > DNF_TEST) return defender;
        return winningTeam;
    }

    int[]@ get_TeamsCurrentScore() const {
        int[] score = {0, 0};
        for (uint i = 0; i < ranking.Length; i++) {
            auto ur = ranking[i];
            auto points = totalUids - i;
            if (ur.time >= DNF_TEST || ur.time <= 0) continue;
            score[ur.team] += points;
        }
        return score;
    }

    TTGSquareState get_WinnerTeams() const {
        auto score = TeamsCurrentScore;
        if (score[0] > score[1]) {
            return TTGSquareState::Player1;
        } else if (score[1] > score[0]) {
            return TTGSquareState::Player2;
        }
        return defender;
    }

    void OnNewTime(const string &in uid, const string &in name, int time, TTGSquareState team) {
        // defenders have priority
        // InsertRankings(teamUids[defender], defender);
        // InsertRankings(teamUids[challenger], challenger);
        InsertRanking(UidRank(uid, name, time, team));
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
        for (uint i = 0; i < ranking.Length; i++) {
            auto other = ranking[i];
            if (ur.time < other.time) {
                ranking.InsertAt(i, ur);
                return;
            } else if (ur.time == other.time && ur.team == defender && other.team == challenger) {
                ranking.InsertAt(i, ur);
                return;
            }
        }
        // if we get here, then we haven't inserted it yet
        ranking.InsertLast(ur);
    }

    int[]@ get_BattleModeCurrentScore() const {
        int[] score = {0, 0};
        for (uint i = 0; i < ranking.Length; i++) {
            auto ur = ranking[i];
            if (ur.time > 0 && ur.time < DNF_TEST) {
                score[ur.team] += 1;
                // ~~todo: maybe test for being over the threshold here and exit early?~~
                // ! no, don't do this -- it means if 3 ppl finish (2 fins required) and the only person on one team to finish was slow, then it won't look like their points counted.
                // guarentees only one winner
                // if (score[ur.team] >= finishesToWin) break;
                // note: this is useful for testing, but in practice it relies on the order of game messages and IsResolved being true -> other players exit after that
            }
        }
        return score;
    }

    TTGSquareState get_WinnerBattleMode() const {
        int winsReq = Math::Max(1, finishesToWin);
        auto score = BattleModeCurrentScore;
        if (score[0] >= winsReq && score[1] >= winsReq) {
            // the match should resolve as soon as one side finishes.
            throw("Two winners in battle mode? Should not be possible.");
        }
        if (score[0] >= winsReq) return TTGSquareState::Player1;
        if (score[1] >= winsReq) return TTGSquareState::Player2;
        //  potential option: If not enough players finish, the team with more points wins
        if (score[0] > score[1]) return TTGSquareState::Player1;
        if (score[0] < score[1]) return TTGSquareState::Player2;
        if (score[0] == score[1]) return defender;
        if (int(ranking.Length) == totalUids) return defender;
        return TTGSquareState::Unclaimed;
    }

    TTGSquareState get_WinnerLegacyMethod() const {
        if (mode != TTGMode::SinglePlayer) throw('cant get legacy winner outside single player');
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
        DnfUnfinishedForTeam(TTGSquareState::Player1);
        DnfUnfinishedForTeam(TTGSquareState::Player2);
    }

    void DnfUnfinishedForTeam(TTGSquareState team) {
        auto @thisTeamsUids = teamUids[team];
        auto @thisTeamsNames = teamNames[team];
        for (uint i = 0; i < thisTeamsUids.Length; i++) {
            auto uid = thisTeamsUids[i];
            if (!uidTimes.Exists(uid))
                SetPlayersTime(uid, thisTeamsNames[i], DNF_TIME, team);
        }
    }

    void CheckFirstResultAt() {
        if (firstResultAt < 0)
            firstResultAt = Time::Now;
    }

    // when not in single player
    void SetPlayersTime(const string &in uid, const string &in name, int time, TTGSquareState team) {
        CheckFirstResultAt();
        uidTimes[uid] = time;
        OnNewTime(uid, name, time, team);
    }

    void SetPlayersTime(TTGSquareState player, int time) {
        CheckFirstResultAt();
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
        if (player == TTGSquareState::Unclaimed) throw("should never pass unclaimed, here");
        if (mode == TTGMode::SinglePlayer) {
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
    string name;

    UidRank(const string &in uid, const string &in name, uint time, TTGSquareState team) {
        this.uid = uid;
        this.time = time;
        this.team = team;
        this.name = name;
    }
}
