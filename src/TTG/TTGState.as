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
    int2 lastColRowRaw = int2(-1, -1);
    // the next expected sequence number of a game event
    int expectedSeq = 0;
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

    bool IsInServer = false;

    ChallengeResultState@ challengeResult = null;
    TTGGameEvent@[] gameLog;
    uint turnCounter = 0;

    bool opt_EnableRecords = false;
    bool opt_FirstRoundForCenter = false;
    bool opt_CannotImmediatelyRepick = false;
    bool opt_RevealMaps = false;
    int opt_AutoDNF = -1;
    // used during battle mode
    int opt_FinishesToWin = 1;
    MapGoal opt_MapGoal = MapGoal::Finish;

    Json::Value@ lastVoteInstruction;

    TicTacGoState(Game::Client@ client) {
        @challengeResult = ChallengeResultState();
        @this.client = client;
        Reset();
    }

    void Reset() {
        mode = TTGMode::Standard;
        state = TTGGameState::PreStart;
        turnCounter = 0;
        gameLog.Resize(0);
        @challengeResult = ChallengeResultState();
        ActiveLeader = TTGSquareState::Unclaimed;
        MyTeamLeader = TTGSquareState::Unclaimed;
        TheirTeamLeader = TTGSquareState::Unclaimed;
        WinningLeader = TTGSquareState::Unclaimed;
        lastColRow = int2(-1, -1);

        boardState.Resize(3);
        for (uint i = 0; i < 3; i++) {
            boardState[i].Resize(3);
            for (uint j = 0; j < 3; j++) {
                boardState[i][j].Reset();
            }
        }
    }

    void OnGameStart() {
        Reset();
        startnew(CoroutineFunc(InitGameOnStart));
    }

    void OnGameEnd() {
        state = TTGGameState::GameFinished;
    }

    void LoadFromGameOpts(const Json::Value@ game_opts) {
        IsInServer = client.roomInfo.use_club_room;
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
        if (IsBattleMode) {
            opt_FinishesToWin = GetGameOptInt(game_opts, 'finishes_to_win', 1);
            opt_FinishesToWin = Math::Min(opt_FinishesToWin, Math::Min(TeamNames[0].Length, TeamNames[1].Length));
        }

        opt_FirstRoundForCenter = GetGameOptBool(game_opts, '1st_round_for_center', false);
        opt_CannotImmediatelyRepick = GetGameOptBool(game_opts, 'cannot_repick', false);
#if DEV
        opt_MapGoal = MapGoal(GetGameOptInt(game_opts, 'map_goal', 0));
#endif

        // if (IsSinglePlayer) opt_FirstRoundForCenter = false;
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
        return GameInfo.TeamNames;
    }

    void InitGameOnStart() {
        while (GameInfo is null) {
            log_trace("InitGameOnStart found null game info, yielding");
            yield();
        }
        while (client.mapsList is null || client.mapsList.Length == 0) {
            log_trace("InitGameOnStart found empty map list, yielding");
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

    bool WasPriorSquare(int col, int row, bool ignoreWinStatus = false) {
        if (ignoreWinStatus)
            return lastColRowRaw.x == col && lastColRowRaw.y == row;
        return lastColRow.x == col && lastColRow.y == row;
    }


    bool InvalidReason(const string &in reason) {
        warn("Move invalid b/c: " + reason);
        return false;
    }


    bool IsValidMove(const string &in msgType, uint col, uint row, TTGSquareState fromPlayer, bool isFromLeader, const string &in lastFromUid) const {
        if (fromPlayer == TTGSquareState::Unclaimed) return InvalidReason("from player == unclaimed");
        if (IsGameFinished) return InvalidReason("game finished");
        if (IsInChallenge || IsInClaim) {
            bool moveIsChallengeRes = msgType == "G_CHALLENGE_RESULT";
            bool moveIsForceEnd = msgType == "G_CHALLENGE_FORCE_END";
            bool moveIsVoteInstructions = msgType == "G_SERVER_EXPECT_VOTE";
            bool isValidType = moveIsChallengeRes || moveIsForceEnd || moveIsVoteInstructions;
            if (!isValidType) return InvalidReason("only challenge result or force end are valid");
            if (moveIsForceEnd || moveIsVoteInstructions) {
                return client.IsPlayerAdminOrMod(lastFromUid) || InvalidReason(msgType + ": only by admin or mod");
            }
            if (IsSinglePlayer && challengeResult.HasResultFor(fromPlayer)) return InvalidReason("got result already");
            if (!IsSinglePlayer && challengeResult.HasResultFor(lastFromUid)) return InvalidReason("got result already: " + challengeResult.GetResultFor(lastFromUid, -1));
            return true;
        } else if (IsWaitingForMove) {
            if (col >= 3 || row >= 3) return InvalidReason("col/row >= 3");
            if (!isFromLeader) return InvalidReason("move not from lead player");
            if (fromPlayer != ActiveLeader && !IsSinglePlayer) return InvalidReason("not from active leader");
            bool moveIsClaiming = msgType == "G_TAKE_SQUARE";
            bool moveIsChallenging = msgType == "G_CHALLENGE_SQUARE";
            if (!moveIsChallenging && !moveIsClaiming) return InvalidReason("move type must be take or challenge square");
            if (opt_CannotImmediatelyRepick && WasPriorSquare(col, row)) return InvalidReason("cannot repick prior square");
            auto sqState = GetSquareState(col, row);
            if (sqState.IsOwnedBy(ActiveLeader)) return InvalidReason("square owned by player");
            if (moveIsChallenging) {
                if (sqState.IsUnclaimed) return InvalidReason("cannot challenge an unclaimed square");
                return !sqState.IsOwnedBy(fromPlayer) || IsSinglePlayer || InvalidReason("owned by player");
            } else if (moveIsClaiming) {
                return sqState.IsUnclaimed || InvalidReason("cannot claim a claimed square");
            }
            return InvalidReason("should have returned true by now");
        }
        return InvalidReason("at end, should have hit a branch");
    }


    void ProcessMove(Json::Value@ msg) {
        while (IsPreStart) yield();
        string msgType = msg['type'];
        auto pl = msg['payload'];
        int seq = pl['seq'];
        bool isReplay = seq < client.GameReplayNbMsgs;
        bool isGmReset = msgType == "GM_RESET";
        if (isGmReset) {
            expectedSeq = seq + 1;
            dev_print('reset expected next sequence number to: ' + expectedSeq);
            return;
        } else if (seq != expectedSeq) {
            warn("Skipping message with sequence number: " + seq + '; expected: ' + expectedSeq);
            return;
        }
        expectedSeq++;
        dev_print('Processing: ' + seq + ', Next Expected Seq ' + expectedSeq);

        if (msgType.StartsWith("GM_")) {
            ProcessGameMasterEvent(msgType, pl);
            return;
        }
        if (!msgType.StartsWith("G_")) {
            warn("Skipping non-game msg: " + msgType + "; " + Json::Write(msg));
            return;
        }
        // skip rematch meta
        if (msgType == "G_REMATCH_INIT") return;
        // deserialize game move; all game moves have a col/row
        uint col, row;
        try {
            col = pl['col'];
            row = pl['row'];
        } catch {
            warn("Exception processing move (col/row): " + getExceptionInfo());
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
            bool moveIsVoteInstructions = msgType == "G_SERVER_EXPECT_VOTE";
            bool isValidType = moveIsChallengeRes || moveIsForceEnd || moveIsVoteInstructions;
            if (!isValidType) throw("not a valid move type: should be impossible");
            if (!challengeResult.active) throw("challenge is not active");
            // primary mutation from each instruction type
            if (moveIsForceEnd) {
                if (!client.IsPlayerAdminOrMod(lastFromUid)) throw("force end from a non admin/mod");
                challengeResult.ForceEnd();
                gameLog.InsertLast(TTGGameEvent_ForceEnd(lastFromUsername, lastFromUid));
                if (!challengeResult.IsResolved)
                    warn("we just force ended the challenge but it did not resolve!");
            } else if (moveIsVoteInstructions) {
                if (!client.IsPlayerAdminOrMod(lastFromUid)) throw("vote instruction from a non admin/mod");
                @lastVoteInstruction = pl;
            } else if (moveIsChallengeRes) {
                if (IsSinglePlayer) {
                    // if we're in a single player game, set a slightly worse time for the inactive player
                    challengeResult.SetPlayersTime(ActiveLeader, int(pl['time']));
                    challengeResult.SetPlayersTime(InactiveLeader, int(pl['time']) + 100);
                } else {
                    challengeResult.SetPlayersTime(lastFromUid, lastFromUsername, int(pl['time']), lastFromTeam);
                }
            } else {
                NotifyError("impossible? unknown move type");
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
                    lastColRowRaw = xy;
                }

                currChallengeRun.Shutdown();
                challengeResult.Reset();
                challengeEndedAt = Time::Now;
                @lastVoteInstruction = null;

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
            if (currChallengeRun !is null) currChallengeRun.Shutdown();
            @currChallengeRun = null;
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

    void ProcessGameMasterEvent(const string &in type, Json::Value@ pl) {
        if (type == "GM_PLAYER_LEFT") {
            if (!IsGameFinished) {
                string uid = pl['uid'];
                string name = pl['username'];
                GameInfo.MovePlayerToBackOfTeam(uid);
                MyLeadersName = TeamNames[MyTeamLeader][0];
                OpposingLeaderName = IsSinglePlayer ? MyLeadersName : TeamNames[TheirTeamLeader][0];
                IAmALeader = GameInfo.teams[MyTeamLeader][0] == client.clientUid;
                // if someone DCs, dnf them
                if (!IsSinglePlayer && challengeResult.active && !challengeResult.HasResultFor(uid)) {
                    warn("DNFing due to player left");
                    challengeResult.SetPlayersTime(uid, name, DNF_TIME, UidToTeam(uid));
                }
            }
        } else if (type == "GM_PLAYER_JOINED") {
            // todo
        } else {
            warn("Skipping GM event: " + type + "; " + Json::Write(pl));
        }
    }


    // challenges and maps


    Json::Value@ currMap;
    int currTrackId;
    string currTrackIdStr;
    string mapUid, mapName;

    int challengePreWaitPeriod = 3000;
    string beginChallengeLatestNonce;
    bool sameAsLastMap = false;
    string lastMapUid;

    void BeginChallengeSoon() {
        // this can happen when replaying game events
        if (!challengeResult.active || !IsInClaimOrChallenge) {
            warn("BeginChallengeSoon returning b/c: !challengeResult.active || !IsInClaimOrChallenge");
            return;
        }
        string myNonce = Crypto::RandomBase64(10);
        beginChallengeLatestNonce = myNonce;
        auto col = challengeResult.col;
        auto row = challengeResult.row;
        auto map = GetMap(col, row);
        @currMap = map;
        currTrackId = map['TrackID'];
        mapUid = map['TrackUID'];
        mapName = map.Get('Name', "???");
        currTrackIdStr = tostring(currTrackId);
        challengeResult.startTime = Time::Now + challengePreWaitPeriod;
        sameAsLastMap = WasPriorSquare(col, row, true) || mapUid == lastMapUid;
        lastMapUid = mapUid;
        trace("Challenge start time: " + challengeResult.startTime);
        trace("Challenge nonce: " + myNonce);
        // autostart if not
        if (!IsInServer) {
            // we sleep for slightly less to avoid race conditions with the launch map button
            sleep(challengePreWaitPeriod - 30);
            // load map immediately if the CR is the same one and the setting is enabled.
            bool crChecks = beginChallengeLatestNonce == myNonce
                && !challengeResult.HasResultFor(client.clientUid)
                && !challengeResult.IsResolved;
            if (crChecks && S_TTG_AutostartMap && !CurrentlyInMap) {
                print("Autostarting map for: " + MyName);
                @currChallengeRun = LocalChallengeRun();
            } else {
                warn("Skipping challenge b/c one of: crChecks failed, challenge not active, not autostart, or currently in map");
                return;
            }
        } else {
            sleep(300);
            bool crChecks = beginChallengeLatestNonce == myNonce
                && !challengeResult.HasResultFor(client.clientUid)
                && !challengeResult.IsResolved;
            if (crChecks) {
                @currChallengeRun = ClubServerChallengeRun();
            } else {
                warn("Skipping challenge b/c one of: crChecks failed, challenge not active");
                return;
            }
        }
        if (currChallengeRun !is null) {
            InitAndRunChallenge();
        }
    }

    void StartLocalChallengeFromButton() {
        @currChallengeRun = LocalChallengeRun();
        currChallengeRun.disableLaunchMapBtn = true;
        InitAndRunChallenge();
    }

    void InitAndRunChallenge() {
        currChallengeRun.Initialize(
            "TTG! - " + string(currMap.Get("Name", "???")), "Go Team " + MyLeadersName + "!",
            mapUid, mapName, currTrackId, sameAsLastMap,
            IsInServer, opt_AutoDNF_ms, opt_EnableRecords,
            ChallengeRunReport(ReportChallengeResult),
            challengeResult
        );
        currChallengeRun.StartRunCoro();
    }

    Json::Value@ GetMap(int col, int row) {
        if (client.mapsList.Length == 0) return null;
        // todo: still an issue with getting maps early?
        int mapIx = row * 3 + col;
        if (mapIx >= int(client.mapsList.Length)) {
            // RESTART MAP
            NotifyError('bad map index '+ col + ", " + row);
            // this issue seems rare, but better to return something than nothing
            return client.mapsList[0];
        }
        if (mapIx < 0) {
            NotifyError('negavive col/row?: ' + col + ", " + row);
            return client.mapsList[0];
        }
        return client.mapsList[mapIx];
    }

    uint challengeEndedAt;
    ChallengeRun@ currChallengeRun = null;

    bool get_challengeRunActive() {
        if (currChallengeRun is null) return false;
        return currChallengeRun.challengeRunActive;
    }

    bool get_disableLaunchMapBtn() {
        if (currChallengeRun is null) return false;
        return currChallengeRun.disableLaunchMapBtn;
    }

    bool get_hideChallengeWindowInServer() {
        if (currChallengeRun is null) return false;
        return currChallengeRun.hideChallengeWindowInServer;
    }

    bool get_shouldExitChallenge() {
        if (currChallengeRun is null) return true;
        return currChallengeRun.shouldExitChallenge;
    }

    uint get_shouldExitChallengeTime() {
        if (currChallengeRun is null) return DNF_TIME;
        return currChallengeRun.shouldExitChallengeTime;
    }

    int get_challengeEndTime() {
        if (currChallengeRun is null) return -1;
        return currChallengeRun.challengeEndTime;
    }

    int get_challengeStartTime() {
        if (currChallengeRun is null) return -1;
        return currChallengeRun.challengeStartTime;
    }

    int get_currGameTime() {
        if (currChallengeRun is null) return -1;
        return currChallengeRun.currGameTime;
    }

    void EndChallenge() {
        if (currChallengeRun is null) return;
        currChallengeRun.EndChallenge();
    }

    // // relative to Time::Now to avoid pause menu strats
    // int challengeStartTime = -1;
    // int playerInitStartTime = -1;
    // int lastPlayerStartTime = -1;
    // int challengeEndTime = -1;
    // int challengeScreenTimeout = -1;
    // int currGameTime = -1;
    // int currPeriod = 15;  // frame time
    // bool challengeRunActive = false;
    // bool disableLaunchMapBtn = false;
    // bool hideChallengeWindowInServer = false;
    // bool showForceEndPrompt = false;
    // bool shouldExitChallenge = false;
    // uint shouldExitChallengeTime = DNF_TIME;
    // bool serverChallengeInExpectedMap = false;
    // uint lastSpamNo = 0;

    // void ResetChallengeState() {
    //     showForceEndPrompt = false;
    //     shouldExitChallenge = false;
    //     hideChallengeWindowInServer = false;
    //     challengeStartTime = -1;
    //     currGameTime = -1;
    //     currPeriod = 15;
    //     serverChallengeInExpectedMap = false;
    // }

    // void RunChallengeAndReportResult() {
    //     ResetChallengeState();
    //     disableLaunchMapBtn = true;
    //     SetLoadingScreenText("TTG! - " + string(currMap.Get("Name", "???")), "Go Team " + MyLeadersName + "!");
    //     yield();
    //     yield();
    //     // join map
    //     challengeRunActive = true;
    //     LoadMapNow(MapUrlTmx(currMap['TrackID']));
    //     startnew(CoroutineFunc(ResetLaunchMapBtnSoon));
    //     while (!CurrentlyInMap) yield();
    //     sleep(50);
    //     // wait for UI sequence to be playing
    //     while (GetApp().CurrentPlayground is null) yield();
    //     auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
    //     while (cp.Players.Length < 1) yield();
    //     auto player = cast<CSmScriptPlayer>(cast<CSmPlayer>(cp.Players[0]).ScriptAPI);
    //     while (cp.UIConfigs.Length < 0) yield();
    //     auto uiConfig = cp.UIConfigs[0];
    //     while (uiConfig.UISequence != CGamePlaygroundUIConfig::EUISequence::Intro) yield();
    //     // re enable the launch map button here, is good enough and pretty close to the first time we can safely re-enable
    //     disableLaunchMapBtn = false;
    //     while (uiConfig.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
    //     yield(); // we don't need to get the time immediately, so give some time for values to update
    //     while (player.StartTime < 0) yield();
    //     HideGameUI::opt_EnableRecords = opt_EnableRecords;
    //     startnew(HideGameUI::OnMapLoad);
    //     auto initNbGhosts = GetCurrNbGhosts();
    //     yield();
    //     yield();
    //     // start of challenge
    //     if (GetApp().PlaygroundScript is null) {
    //         EndChallenge();
    //         return;
    //     }
    //     currGameTime = GetApp().PlaygroundScript.Now;
    //     // ! timer bugs sometimes on start hmm
    //     challengeStartTime = Time::Now + (player.StartTime - currGameTime);
    //     playerInitStartTime = player.StartTime;
    //     lastPlayerStartTime = player.StartTime;
    //     if (challengeStartTime < int(Time::Now)) {
    //         warn("challengeStartTime is in the past; now - start = " + (int(Time::Now) - challengeStartTime) + ". setting to 1.5s in the future.");
    //         // the timer should always start at -1.5s, so set it 1.5s in the future
    //         challengeStartTime = Time::Now + 1500;
    //     }

    //     log_info("Set challenge start time: " + challengeStartTime);
    //     // wait for finish timer
    //     int duration;
    //     bool hasFinished = false;
    //     while (true) {
    //         if (!hasFinished && uiConfig.UISequence == CGamePlaygroundUIConfig::EUISequence::Finish) {
    //             hasFinished = true;
    //             while (initNbGhosts == GetCurrNbGhosts()) yield();
    //             auto runTime = GetMostRecentGhostTime();
    //             auto endTime = lastPlayerStartTime + runTime;
    //             duration = endTime - playerInitStartTime;
    //             challengeEndTime = challengeStartTime + duration;
    //             // report result
    //             ReportChallengeResult(duration);
    //         }
    //         int oppTime = 0;
    //         int timeLeft = DNF_TEST;
    //         bool shouldDnf = false;
    //         if (!hasFinished) {
    //             duration = Time::Now - challengeStartTime;
    //             lastPlayerStartTime = player.StartTime;
    //             initNbGhosts = GetCurrNbGhosts();
    //             oppTime = challengeResult.ranking.Length > 0 ? challengeResult.ranking[0].time : DNF_TIME;
    //             timeLeft = oppTime + opt_AutoDNF_ms - duration;
    //             shouldDnf = opt_AutoDNF_ms > 0 && timeLeft <= 0;
    //         }
    //         // if the challenge is resolved (e.g., via force ending) then we want to exit out
    //         // ~~also if we already have a result~~ leave players in the map while other ppl haven't finished yet
    //         shouldExitChallenge = challengeResult.IsResolved;
    //         if (shouldDnf || shouldExitChallenge || GetApp().PlaygroundScript is null || uiConfig is null) {
    //             log_trace('should dnf, or exit, or player already did.');
    //             if (shouldDnf) {
    //                 log_warn("shouldDnf. time left: " + timeLeft + "; oppTime: " + oppTime + ", duration=" + duration);
    //             }
    //             // don't report a time if the challenge is resolved b/c it's an invalid move
    //             if (!shouldExitChallenge && !hasFinished)
    //                 ReportChallengeResult(DNF_TIME); // more than 24 hrs, just
    //             // if we are still in the map we want to let hte user know before we exit
    //             if (shouldExitChallenge) {
    //                 shouldExitChallengeTime = Time::Now + 3000;
    //                 AwaitShouldExitTimeOrMapLeft();
    //             }
    //             // player quit (or auto DNF)
    //             warn("Map left. Either: player quit, autodnf, or challenge resolved");
    //             break;
    //         }
    //         currGameTime = GetApp().PlaygroundScript.Now;
    //         if (!hasFinished)
    //             challengeEndTime = Time::Now;
    //         currPeriod = GetApp().PlaygroundScript.Period;
    //         yield();
    //     }
    //     EndChallenge();
    // }

    // bool ShouldBlackout() {
    //     return false;
    // }

    // // todo: refactor this and the above to use mostly the same logic, and abstract differences
    // void InServerRunChallenge() {
    //     // warn('InServerRunChallenge');
    //     if (!IsInServer) {
    //         warn("InServerRunChallenge called when not in a server");
    //         return;
    //     }
    //     ResetChallengeState();
    //     SetLoadingScreenText("TTG! - " + string(currMap.Get("Name", "???")), "Go Team " + MyLeadersName + "!");
    //     auto app = cast<CGameManiaPlanet>(GetApp());
    //     // wait for us to join the server if we haven't yet
    //     while (!CurrentlyInMap) yield();
    //     // warn('InServerRunChallenge in map');
    //     auto cp = cast<CSmArenaClient>(app.CurrentPlayground);
    //     while (cp.Map is null) yield();
    //     while (app.Network.ClientManiaAppPlayground is null) yield();
    //     sleep(250);
    //     // warn('setting challenge run active');
    //     challengeRunActive = true;
    //     auto cmap = app.Network.ClientManiaAppPlayground;
    //     auto currUid = cp.Map.MapInfo.MapUid;
    //     string expectedUid = currMap.Get('TrackUID', '??');
    //     if (expectedUid.Length < 5) warn("Expected uid is bad! " + expectedUid);
    //     serverChallengeInExpectedMap = expectedUid == currUid;
    //     // warn('serverChallengeInExpectedMap: ' + tostring(serverChallengeInExpectedMap));
    //     if (!serverChallengeInExpectedMap) {
    //         auto net = app.Network;
    //         net.PlaygroundClientScriptAPI.RequestGotoMap(expectedUid);
    //         startnew(CoroutineFunc(SpamVoteYesForABit));
    //         // todo: monitor vote?
    //         // wait for start
    //         while (app.RootMap is null || app.RootMap.MapInfo.MapUid != expectedUid) yield();
    //         while (app.Network.ClientManiaAppPlayground is null) yield();
    //         while (app.CurrentPlayground is null) yield();
    //         sleep(100);
    //     } else {
    //         bool reqAlreadyInProg = app.Network.PlaygroundClientScriptAPI.Request_IsInProgress;
    //         // we might be rejoining an ongoing map, only send request restart if there are no times yet
    //         app.Network.PlaygroundClientScriptAPI.RequestRestartMap();
    //         // while (!reqAlreadyInProg && !app.Network.PlaygroundClientScriptAPI.Request_IsInProgress) yield();
    //         startnew(CoroutineFunc(SpamVoteYesForABit));
    //         while (app.Network.PlaygroundClientScriptAPI.Request_IsInProgress || cmap.UI.UISequence == CGamePlaygroundUIConfig::EUISequence::Playing) yield();
    //     }
    //     serverChallengeInExpectedMap = true;
    //     while (cmap !is null && cmap.UI !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Intro) yield();
    //     if (cmap is null || cmap.UI is null) return; // exited playground
    //     while (cmap !is null && cmap.UI !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
    //     if (cmap is null || cmap.UI is null) return; // exited playground
    //     // Now that we're playing, we need to figure out if we're in a warmup or not.

    //     HideGameUI::opt_EnableRecords = opt_EnableRecords;
    //     startnew(HideGameUI::OnMapLoad);
    //     auto initNbGhosts = GetCurrNbGhosts();

    //     auto player = FindLocalPlayersInPlaygroundPlayers(GetApp());
    //     while (cmap.UILayers.Length < 15) yield();
    //     while (cmap !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
    //     sleep(100);
    //     while (cmap !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
    //     while (IsInWarmUp()) yield();
    //     sleep(100);
    //     while (cmap !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
    //     if (cmap is null) return;
    //     hideChallengeWindowInServer = true;
    //     sleep(750);
    //     if ((cmap is null || cmap.Playground is null)) {
    //         EndChallenge();
    //         return;
    //     }
    //     currGameTime = cmap.Playground.GameTime;
    //     challengeStartTime = Time::Now + (player.StartTime - currGameTime);
    //     playerInitStartTime = player.StartTime;
    //     lastPlayerStartTime = player.StartTime;
    //     // while (player.CurrentRaceTime > 0) yield(); // wait for current race time to go negative
    //     if (challengeStartTime < int(Time::Now)) {
    //         warn("challengeStartTime is in the past; now - start = " + (int(Time::Now) - challengeStartTime) + ".");
    //         // the timer should always start at -1.5s, so set it 1.5s in the future
    //         // challengeStartTime = Time::Now + 1500;
    //     }

    //     log_info("Set challenge start time: " + challengeStartTime);
    //     // wait for finish timer
    //     int duration;
    //     bool hasFinished = false;
    //     while (true) {
    //         if (cmap is null || cmap.UI is null || app.Network.PlaygroundClientScriptAPI is null) break;
    //         if (lastSpamNo + 5000 < Time::Now) {
    //             if (app.Network.PlaygroundClientScriptAPI.Request_IsInProgress && challengeResult.IsEmpty) {
    //                 // if there's a vote, and there are no scores yet, vote no a few times
    //                 // this can happen if a player rejoins
    //                 startnew(CoroutineFunc(SpamVoteNoForABit));
    //                 lastSpamNo = Time::Now;
    //             } else if (app.Network.PlaygroundClientScriptAPI.Request_IsInProgress && !challengeResult.IsResolved) {
    //                 startnew(CoroutineFunc(SpamVoteNoForABitWhileStillUnresolved));
    //                 lastSpamNo = Time::Now;
    //             }
    //         }
    //         if (!hasFinished && cmap.UI.UISequence == CGamePlaygroundUIConfig::EUISequence::Finish) {
    //             hasFinished = true;
    //             while (initNbGhosts == GetCurrNbGhosts()) yield();
    //             auto runTime = GetMostRecentGhostTime();
    //             auto endTime = lastPlayerStartTime + runTime;
    //             duration = endTime - playerInitStartTime;
    //             challengeEndTime = challengeStartTime + duration;
    //             ReportChallengeResult(duration);
    //         }
    //         int oppTime = 0;
    //         int timeLeft = DNF_TEST;
    //         bool shouldDnf = false;
    //         if (!hasFinished) {
    //             duration = Time::Now - challengeStartTime;
    //             lastPlayerStartTime = player.StartTime;
    //             initNbGhosts = GetCurrNbGhosts();
    //             oppTime = challengeResult.ranking.Length > 0 ? challengeResult.ranking[0].time : DNF_TIME;
    //             timeLeft = oppTime + opt_AutoDNF_ms - duration;
    //             shouldDnf = opt_AutoDNF_ms > 0 && timeLeft <= 0;
    //         }
    //         // if the challenge is resolved (e.g., via force ending) then we want to exit out
    //         // ~~also if we already have a result~~ leave players in the map while other ppl haven't finished yet
    //         shouldExitChallenge = challengeResult.IsResolved;
    //         if (shouldDnf || shouldExitChallenge || GetApp().CurrentPlayground is null && app.Switcher.ModuleStack.Length > 0) {
    //             log_trace('should dnf, or exit, or player already did.');
    //             if (shouldDnf) {
    //                 log_warn("shouldDnf. time left: " + timeLeft + "; oppTime: " + oppTime + ", duration=" + duration);
    //             }
    //             // don't report a time if the challenge is resolved b/c it's an invalid move
    //             if (!shouldExitChallenge && !hasFinished)
    //                 ReportChallengeResult(DNF_TIME);
    //             while (!challengeResult.IsResolved) yield();
    //             shouldExitChallengeTime = Time::Now + 3000;
    //             AwaitShouldExitTimeOrMapLeft();
    //             break;
    //         }
    //         currGameTime = cmap.Playground.GameTime;
    //         if (!hasFinished)
    //             challengeEndTime = Time::Now;
    //         currPeriod = app.Network.PlaygroundInterfaceScriptHandler.Period;
    //         yield();
    //     }
    //     EndChallenge();
    // }

    // void SpamVoteYesForABit() {
    //     auto app = cast<CGameManiaPlanet>(GetApp());
    //     auto net = app.Network;
    //     sleep(500);
    //     bool voteInProg = false;
    //     bool voteEnded = false;
    //     for (uint i = 0; i < 16; i++) {
    //         if (net.PlaygroundClientScriptAPI !is null) {
    //             if (net.PlaygroundClientScriptAPI.Request_IsInProgress) {
    //                 voteInProg = true;
    //                 net.PlaygroundClientScriptAPI.Vote_Cast(true);
    //             } else if (voteInProg) {
    //                 voteEnded = true;
    //                 voteInProg = false;
    //                 // break;
    //             }
    //         }
    //         sleep(500);
    //     }
    // }

    // void SpamVoteNoForABit() {
    //     auto app = cast<CGameManiaPlanet>(GetApp());
    //     auto net = app.Network;
    //     sleep(500);
    //     for (uint i = 0; i < 8; i++) {
    //         if (net.PlaygroundClientScriptAPI !is null) {
    //             if (net.PlaygroundClientScriptAPI.Request_IsInProgress)
    //                 net.PlaygroundClientScriptAPI.Vote_Cast(false);
    //         }
    //         sleep(500);
    //     }
    // }

    // void SpamVoteNoForABitWhileStillUnresolved() {
    //     auto app = cast<CGameManiaPlanet>(GetApp());
    //     auto net = app.Network;
    //     for (uint i = 0; i < 8; i++) {
    //         uint start = Time::Now;
    //         bool keepChecking = net.PlaygroundClientScriptAPI !is null && net.PlaygroundClientScriptAPI.Request_IsInProgress && !challengeResult.IsResolved;
    //         while (Time::Now < start + 500 && keepChecking) {
    //             yield();
    //             keepChecking = net.PlaygroundClientScriptAPI !is null && net.PlaygroundClientScriptAPI.Request_IsInProgress && !challengeResult.IsResolved;
    //         }
    //         if (!keepChecking) break;
    //         net.PlaygroundClientScriptAPI.Vote_Cast(false);
    //     }
    // }

    // // uses shouldExitChallengeTime
    // void AwaitShouldExitTimeOrMapLeft() {
    //     while (shouldExitChallengeTime > Time::Now && CurrentlyInMap) yield();
    // }

    // void EndChallenge() {
    //     challengeRunActive = false;
    //     if (!IsInServer && GameInfo !is null && !IsPreStart)
    //         startnew(ReturnToMenu);
    // }

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

    void Reset(bool hard = false) {
        startTime = -1;
        active = false;
        if (hard) {
            player1Time = -1;
            player2Time = -1;
            uidTimes.DeleteAll();
            ranking.Resize(0);
            firstResultAt = -1;
        }
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
        int[] count = {0, 0};
        // if the teams aren't even, then we don't want to count more scores on the larger team
        int maxPlayers = Math::Min(teamUids[0].Length, teamUids[1].Length);
        for (uint i = 0; i < ranking.Length; i++) {
            auto ur = ranking[i];
            if (count[ur.team] >= maxPlayers) continue;
            count[ur.team] += 1;
            auto points = totalUids - i;
            if (ur.time >= DNF_TEST || ur.time <= 0) continue;
            score[ur.team] += points;
        }
        return score;
    }

    // if the teams are uneven, the smaller team gets the bias
    TTGSquareState get_WinnerTeams() const {
        int teamDiff = int(teamUids[0].Length) - teamUids[1].Length;
        bool evenTeams = teamDiff == 0;
        TTGSquareState defaultWinner = evenTeams ? defender : (teamDiff < 0 ? TTGSquareState::Player1 : TTGSquareState::Player2);
        auto score = TeamsCurrentScore;
        if (score[0] > score[1]) {
            return TTGSquareState::Player1;
        } else if (score[1] > score[0]) {
            return TTGSquareState::Player2;
        }
        // if all players dnfd, return defenders
        if (score[0] == 0) return defender;
        return defaultWinner;
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
        warn("Don't call this from teams or battle mode");
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
