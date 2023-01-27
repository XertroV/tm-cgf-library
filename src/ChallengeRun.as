funcdef void ChallengeRunReport(int duration);
funcdef Json::Value@ CR_GetExpectedVote();
funcdef void CR_SetExpectedVote(const string &in type, const string &in question);

class ChallengeRun {
    protected bool SHUTDOWN = false;

    // relative to Time::Now to avoid pause menu strats
    int challengeStartTime = -1;
    int playerInitStartTime = -1;
    int lastPlayerStartTime = -1;
    int challengeEndTime = -1;
    int currGameTime = -1;
    int currPeriod = 15;  // frame time
    bool challengeRunActive = false;
    bool disableLaunchMapBtn = false;
    bool hideChallengeWindowInServer = false;
    bool shouldExitChallenge = false;
    uint shouldExitChallengeTime = DNF_TIME;
    int initNbGhosts = 0;
    int duration = -1;
    bool opt_EnableRecords = false;
    int opt_AutoDNF_ms = -1;
    CSmScriptPlayer@ player;
    ChallengeResultState@ challengeResult;

    bool runInServer = false;

    bool hasFinished = false;
    bool runActive = false;

    // should be true when this is the same map as the last map
    bool mapSameAsLast = false;

    string loadingScreenTop;
    string loadingScreenBottom;
    string mapUid;
    string mapName;
    int trackID;
    bool shouldManageVotes;

    ChallengeRunReport@ reportFunc;
    CR_GetExpectedVote@ getExpectedVote;
    CR_SetExpectedVote@ setExpectedVote;

    bool initialized = false;

    ChallengeRun() {
        startnew(CoroutineFunc(this.EnsureInit));
    }

    void Initialize(
            const string &in loadingScreenTop,
            const string &in loadingScreenBottom,
            const string &in mapUid,
            const string &in mapName,
            int trackID,
            bool mapSameAsLast,
            bool runInServer,
            bool shouldManageVotes,
            int opt_AutoDNF_ms, // = -1,
            bool opt_EnableRecords, // = false,
            ChallengeRunReport@ reportFunc,
            CR_GetExpectedVote@ getExpectedVote,
            CR_SetExpectedVote@ setExpectedVote,
            ChallengeResultState@ challengeResult
        ) {
        this.initialized = true;

        this.opt_EnableRecords = opt_EnableRecords;
        this.opt_AutoDNF_ms = opt_AutoDNF_ms;

        if (reportFunc is null) throw('report func null!');
        if (getExpectedVote is null) throw('getExpectedVote null!');
        if (setExpectedVote is null) throw('setExpectedVote null!');
        @this.reportFunc = reportFunc;
        @this.getExpectedVote = getExpectedVote;
        @this.setExpectedVote = setExpectedVote;
        @this.challengeResult = challengeResult;

        this.loadingScreenTop = loadingScreenTop;
        this.loadingScreenBottom = loadingScreenBottom;

        this.trackID = trackID;
        this.mapUid = mapUid;
        this.mapName = mapName;
        this.mapSameAsLast = mapSameAsLast;
        this.runInServer = runInServer;
        this.shouldManageVotes = shouldManageVotes;
    }

    void EnsureInit() {
        yield();
        if (!initialized) {
            throw("You must call .Initialize immediately after instantiating a ChallengeRun");
        }
    }

    void Shutdown() {
        this.SHUTDOWN = true;
        @getExpectedVote = null;
        @setExpectedVote = null;
        @reportFunc = null;
    }

    /**
     * Run order:
     * bool PreconditionsMet(): in the expected state
     * PreActivate(): loading screen, etc
     * Activate(): flag active, load map or do voting
     * PostActivate(): correct map loaded, wait for round to start
     * bool PreMain_CheckExit(): ensure we're still in the playground etc
     * PreMain(): set initial variables
     * bool UpdateMain(): called every frame, monitors time and reports results; false to break
     * PostMain(): after done, cleanup
     */
    void RunNowAsync() {
        // ** CHECKS
        if (!PreconditionsMet()) return;
        // ** INIT
        trace('ChallengeRun.RunNowAsync: PreActivate');
        PreActivate();
        trace('ChallengeRun.RunNowAsync: Activate');
        Activate();
        sleep(500);
        trace('ChallengeRun.RunNowAsync: PostActivate');
        PostActivate();
        // ** CHALLENGE READY
        trace('ChallengeRun.RunNowAsync: PreMain_CheckExit');
        if (PreMain_CheckExit()) return;
        // ** Start
        trace('ChallengeRun.RunNowAsync: PreMain');
        PreMain();
        yield();
        trace('ChallengeRun.RunNowAsync: UpdateMain');
        while (UpdateMain()) yield();
        // ** END
        trace('ChallengeRun.RunNowAsync: PostMain');
        PostMain();
    }


    // check preconditions and log if exiting
    bool PreconditionsMet() {
        return true;
    }

    void SetLoadingScreen() {
        SetLoadingScreenText(loadingScreenTop, loadingScreenBottom);
    }

    /*
        load map and wait for load to be complete
        - local: load and wait to be in a map, playground not null
        - server: voting loops, wait for map to be correct
     */
    void Activate_LoadChallengeMapAsync() {
        throw("Override me");
    }

    // One person should run this to manage the vote to the next map
    void Activate_ManageVotesAsync() {
        return;
    }

    // terminates when we are in the intro
    void OnReady_WaitForPlayers() {
        while (GetApp().Network.ClientManiaAppPlayground is null) yield();
        while (cast<CSmArenaClient>(GetApp().CurrentPlayground) is null) yield();
        yield();
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        while (cp !is null && cp.Players.Length < 1) yield();
        // auto player = cast<CSmScriptPlayer>(cast<CSmPlayer>(cp.Players[0]).ScriptAPI);
        // cmap never null
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        while (cmap.UI is null) yield();
    }

    void OnReady_WaitForUI() {
        while (GetApp().CurrentPlayground is null) yield();
        while (GetApp().Network.ClientManiaAppPlayground is null) yield();
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        while (cmap.UI is null) yield();
    }

    void OnReady_WaitForUISequences() {
        throw("override me");
        // while (cp !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Intro) yield();
    }

    bool PreMain_CheckExit() {
        auto app = GetApp();
        return app.CurrentPlayground is null
            || app.Network.ClientManiaAppPlayground is null
            || app.Network.ClientManiaAppPlayground.Playground is null;
    }

    void StartRunCoro() {
        startnew(CoroutineFunc(this.RunNowAsync));
    }

    void PreActivate() {
        if (SHUTDOWN) return;
        SetLoadingScreen();
    }

    void Activate() {
        if (SHUTDOWN) return;
        runActive = true;
        // load map / join server
        // wait for map, currPG to load
        // in server: change map if need be
        if (shouldManageVotes)
            startnew(CoroutineFunc(this.Activate_ManageVotesAsync));
        Activate_LoadChallengeMapAsync();
    }

    void PostActivate() {
        if (SHUTDOWN) return;
        OnReady_WaitForPlayers();
        OnReady_WaitForUI();
        OnReady_WaitForUISequences();

        // wait for players, ui configs
        // wait for intro sequence

        // wait for playing sequence
        // wait for player StartTime
    }

    void PreMain() {
        if (SHUTDOWN) return;
        // records hide/show
        HideGameUI::opt_EnableRecords = opt_EnableRecords;
        startnew(HideGameUI::OnMapLoad);

        // init track ghost, etc
        initNbGhosts = GetCurrNbGhosts();

        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        if (cmap is null || cp is null) return;
        @player = FindLocalPlayersInPlaygroundPlayers(GetApp());
        while (player is null) {
            yield();
            @player = FindLocalPlayersInPlaygroundPlayers(GetApp());
        }

        while (!SHUTDOWN && player.StartTime < 0) yield();
        while (!SHUTDOWN && cp.Arena.Rules.RulesStateStartTime > uint(2<<30)) yield();
        // we can afford to wait a little to avoid race conditions with timers by acting too early
        sleep(500);
        if (SHUTDOWN || cp is null || cmap is null) return;
        // set start time
        currGameTime = cmap.Playground.GameTime;
        // auto roundStartTime = cp.Arena.Rules.RulesStateStartTime;
        auto roundStartTime = player.StartTime;
        challengeStartTime = Time::Now + (roundStartTime - currGameTime);
        playerInitStartTime = roundStartTime;
        lastPlayerStartTime = roundStartTime;
        // while (player.CurrentRaceTime > 0) yield(); // wait for current race time to go negative
        if (challengeStartTime < int(Time::Now)) {
            warn("challengeStartTime is in the past; now - start = " + (int(Time::Now) - challengeStartTime) + ".");
            // the timer should always start at -1.5s, so set it 1.5s in the future
            challengeStartTime = Time::Now + 1500;
        }

        log_info("Set challenge start time: " + challengeStartTime + " (now: " + Time::Now + ")");
        log_info("roundStartTime: " + roundStartTime);
        log_info("playerInitStartTime: " + playerInitStartTime);
        log_info("lastPlayerStartTime: " + lastPlayerStartTime);
        // wait for finish timer
        hasFinished = false;
    }

    // check if the player finished
    bool Main_Check_Finish() {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        if (cmap is null) return false;
        return cmap.UI.UISequence == CGamePlaygroundUIConfig::EUISequence::Finish;
    }

    // check if we should exit the main loop
    bool Main_Check_ShouldExit() {
        throw('override me');
        return false;
    }

    // for voting in server mode; will terminate UpdateMain if false is returned.
    bool Main_Pre_Check_Finish() {
        return true;
    }

    bool firstRun = true;
    void LogFirstRunOnly(const string &in msg) {
        if (!firstRun) return;
        print(msg);
    }

    // return true to continue, false to break
    bool UpdateMain() {
        if (SHUTDOWN) return false;
        // **** CHECK VOTES
        LogFirstRunOnly("[ChallengeRun::UpdateMain] Check Votes");
        if (!Main_Pre_Check_Finish()) return false;
        // **** CHECK FINISH
        // - check for finish
        // -- get time from ghost
        // -- set vars
        // -- report result
        LogFirstRunOnly("[ChallengeRun::UpdateMain] Check Finish");
        if (!hasFinished && Main_Check_Finish()) {
            hasFinished = true;
            while (initNbGhosts == GetCurrNbGhosts()) yield();
            auto runTime = GetMostRecentGhostTime();
            auto endTime = lastPlayerStartTime + runTime;
            duration = endTime - playerInitStartTime;
            challengeEndTime = challengeStartTime + duration;
            log_info("Finished run");
            log_info("initNbGhosts: " + initNbGhosts);
            log_info("GetCurrNbGhosts: " + GetCurrNbGhosts());
            log_info("ghost runTime: " + runTime);
            log_info("lastPlayerStartTime: " + lastPlayerStartTime);
            log_info("playerInitStartTime: " + playerInitStartTime);
            log_info("endTime: " + endTime);
            log_info("duration: " + duration);
            log_info("challengeStartTime: " + challengeStartTime);
            log_info("challengeEndTime: " + challengeEndTime);
            // report result
            ReportChallengeResult(duration);
        }
        // **** UPDATE NOT FINISHED
        // - if not finished
        // -- update duration, start time, nb ghosts, opponent time, time left (if dnf), shouldDnf flag
        LogFirstRunOnly("[ChallengeRun::UpdateMain] Update Not-Finish (finished? " + tostring(hasFinished) + ")");
        int oppTime = 0;
        int timeLeft = DNF_TEST;
        bool shouldDnf = false;
        if (!hasFinished) {
            duration = Time::Now - challengeStartTime;
            if (player.StartTime != lastPlayerStartTime) {
                lastPlayerStartTime = player.StartTime;
                log_info("updated lastPlayerStartTime: " + lastPlayerStartTime);
            }
            initNbGhosts = GetCurrNbGhosts();
            oppTime = challengeResult.ranking.Length > 0 ? challengeResult.ranking[0].time : DNF_TIME;
            timeLeft = oppTime + opt_AutoDNF_ms - duration;
            shouldDnf = opt_AutoDNF_ms > 0 && timeLeft <= 0;
        }

        // **** CHECK EXIT LOOP
        // - check if challenge resolved, or should DNF, or null pg, etc
        // -- maybe report dnf time
        // -- set exit challenge time
        // -- break loop
        LogFirstRunOnly("[ChallengeRun::UpdateMain] Check Should Exit");
        // if the challenge is resolved (e.g., via force ending) then we want to exit out
        // ~~also if we already have a result~~ leave players in the map while other ppl haven't finished yet
        shouldExitChallenge = challengeResult.IsResolved;
        if (shouldDnf || shouldExitChallenge || Main_Check_ShouldExit()) {
            LogFirstRunOnly("[ChallengeRun::UpdateMain] ShouldExit = True");
            log_trace('should dnf, or exit, or player already did.');
            if (shouldDnf) {
                log_warn("shouldDnf. time left: " + timeLeft + "; oppTime: " + oppTime + ", duration=" + duration);
            }
            // don't report a time if the challenge is resolved b/c it's an invalid move
            if (!shouldExitChallenge && !hasFinished)
                ReportChallengeResult(DNF_TIME); // more than 24 hrs, just
            // if we are still in the map we want to let hte user know before we exit
            if (shouldExitChallenge || challengeResult.IsResolved) {
                shouldExitChallengeTime = Time::Now + 3000;
                AwaitShouldExitTimeOrMapLeft();
            }
            // player quit (or auto DNF)
            warn("Map left. Either: player quit, autodnf, or challenge resolved");
            return false;
        }
        // ** UPDATE
        // - update game time, period, etc
        LogFirstRunOnly("[ChallengeRun::UpdateMain] Update Time");
        currGameTime = GetApp().Network.ClientManiaAppPlayground.Playground.GameTime;
        if (!hasFinished)
            challengeEndTime = Time::Now;
        currPeriod = GetApp().Network.PlaygroundInterfaceScriptHandler.Period;
        LogFirstRunOnly("[ChallengeRun::UpdateMain] Done");
        firstRun = false;
        return true;
    }

    void PostMain() {
        EndChallenge();
    }

    void ReportChallengeResult(int duration) {
        this.reportFunc(duration);
    }

    // uses shouldExitChallengeTime
    void AwaitShouldExitTimeOrMapLeft() {
        while (shouldExitChallengeTime > Time::Now && CurrentlyInMap) yield();
    }

    void EndChallenge() {
        challengeRunActive = false;
        //  && GameInfo !is null && !IsPreStart
        if (!runInServer)
            startnew(ReturnToMenu);
    }
}


class LocalChallengeRun : ChallengeRun {
    LocalChallengeRun() {
        super();
    }

    void Activate_LoadChallengeMapAsync() override {
        challengeRunActive = true;
        LoadMapNow(MapUrlTmx(trackID));
        startnew(CoroutineFunc(ResetLaunchMapBtnSoon));
    }

    void ResetLaunchMapBtnSoon() {
        // prevents softlock if map cannot load (occasionally happens)
        sleep(5000);
        disableLaunchMapBtn = false;
    }

    void OnReady_WaitForUISequences() override {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        while (cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Intro) yield();
        // re enable the launch map button here, is good enough and pretty close to the first time we can safely re-enable
        disableLaunchMapBtn = false;
        while (cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        yield(); // we don't need to get the time immediately, so give some time for values to update
    }

    bool Main_Check_ShouldExit() override {
        return GetApp().PlaygroundScript is null || GetApp().CurrentPlayground is null;
    }
}

class ClubServerChallengeRun : ChallengeRun {
    ClubServerChallengeRun() {
        super();
    }

    bool PreconditionsMet() override {
        return true;
    }

    void PreActivate() override {
        ChallengeRun::PreActivate();
        while (!CurrentlyInMap) yield();
    }

    void Activate_ManageVotesAsync() override {
        if (!shouldManageVotes) return;
        // wait a bit to make sure we should still be going, and to get the latest vote instructions
        sleep(250);
        do {
            while (!SHUTDOWN && Update_ManageVotesAsync()) yield();
        } while (!SHUTDOWN && !InExpectedMap());
        setExpectedVote("VOTE_DONE", "");
    }

    bool Update_ManageVotesAsync() {
        if (SHUTDOWN || !shouldManageVotes) return false;
        auto app = GetApp();
        if (app.CurrentPlayground is null
            || app.Network.ClientManiaAppPlayground is null
            || app.Network.PlaygroundClientScriptAPI is null) return true;
        auto voteInst = getExpectedVote();
        if (voteInst !is null) {
            if (voteInst.GetType() == Json::Type::Object) {
                if (voteInst.Get('type', '??') == "VOTE_DONE") {
                    return false;
                }
            }
        }
        return UpdateVoteToChangeMap();
    }

    void Activate_LoadChallengeMapAsync() override {
        auto app = GetApp();
        while (app.CurrentPlayground is null) yield();
        auto cp = cast<CSmArenaClient>(app.CurrentPlayground);
        while (cp.Map is null) yield();
        while (app.Network.ClientManiaAppPlayground is null) yield();
        auto cmap = app.Network.ClientManiaAppPlayground;
        // warn('setting challenge run active');
        challengeRunActive = true;
        // todo: flag for first server joining. if not, then we always want to vote to restart. if yes, then we'll just accept it as an ongoing game.
        if (SHUTDOWN) return;
        while (!SHUTDOWN && UpdateLoadMapByVoting()) yield();
        // do {
        //     while (app.Network.ClientManiaAppPlayground is null) yield();
        //     @cmap = app.Network.ClientManiaAppPlayground;
        //     while (!InExpectedMap() && IsPlayingOrFinished(cmap.UI.UISequence)) {
        //         if (cp.Arena.Rules.RulesStateStartTime < uint(-1000))
        //             priorRulesStart = cp.Arena.Rules.RulesStateStartTime;
        //         // LoadExpectedMapByVoting();
        //         sleep(250);
        //     }
        //     // while (true) {
        //     //     yield();
        //     //     if (SHUTDOWN) return;
        //     //     @cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        //     //     if (cp is null || cp.Arena is null || cp.Arena.Rules is null) continue;
        //     //     auto newRulesStart = cp.Arena.Rules.RulesStateStartTime;
        //     //     trace("waiting for new rules; prior: " + priorRulesStart + "; new: " + newRulesStart);
        //     //     if (newRulesStart > priorRulesStart && newRulesStart < uint(-1000)) break;
        //     // }
        // } while (!SHUTDOWN && !InExpectedMap());
    }

    bool UpdateLoadMapByVoting() {
        if (SHUTDOWN) return false;
        auto @voteInst = this.getExpectedVote();
        // waiting for voting instructions
        if (voteInst is null) return true;
        // no more votes expected
        switch (voteInst.GetType()) {
            case Json::Type::Object: {
                string type = voteInst.Get('type', '??');
                if (type == "VOTE_DONE") return false;
                if (type == "VOTE_WAIT") return true;
                if (type == "VOTE_QUESTION")
                    return CheckExpectedVote(voteInst);
                warn("Unknown vote msg: " + Json::Write(voteInst));
            }
            case Json::Type::Null:
            default: break;
        }
        warn("Unknown JSON type: " + tostring(voteInst.GetType()));
        return false;
    }

    bool CheckExpectedVote(Json::Value@ vi) {
        auto net = GetApp().Network;
        if (net is null || net.PlaygroundClientScriptAPI is null) return true;
        if (!net.InCallvote) return true;
        auto pgcsa = net.PlaygroundClientScriptAPI;
        if (!pgcsa.Vote_CanVote) return true;
        expectedPromptEnd = vi.Get('question', '??');
        bool voteYes = VoteQuestionIsExpected(pgcsa);
        pgcsa.Vote_Cast(voteYes);
        warn("Voted: " + tostring(voteYes) + " for question: " + pgcsa.Vote_Question);
        return true;
    }

    bool IsPlayingOrFinished(CGamePlaygroundUIConfig::EUISequence seq) {
        return seq == CGamePlaygroundUIConfig::EUISequence::Playing
            || seq == CGamePlaygroundUIConfig::EUISequence::Finish;
    }

    void OnReady_WaitForUISequences() override {
        auto app = GetApp();
        auto cmap = app.Network.ClientManiaAppPlayground;
        while (cmap.UILayers.Length < 15) yield();
        while (cmap !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        sleep(250);
        while (cmap !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        while (IsInWarmUp()) yield();
        sleep(250);
        while (cmap !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        hideChallengeWindowInServer = true;
    }

    // uint lastVotedNo = 0;
    // return false to exit main loop
    bool Main_Pre_Check_Finish() override {
        auto net = GetApp().Network;
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        auto pcsapi = GetApp().Network.PlaygroundClientScriptAPI;
        if (cmap is null || cmap.UI is null || pcsapi is null)
            return false;
        // if (net.InCallvote && pcsapi.Vote_CanVote && lastVotedNo + 60000 < Time::Now) {
        //     warn("Voting false for unexpected vote: " + pcsapi.Vote_Question);
        //     pcsapi.Vote_Cast(false);
        //     lastVotedNo = Time::Now;
        // }
        return true;
    }

    bool Main_Check_ShouldExit() override {
        return GetApp().CurrentPlayground is null && GetApp().Switcher.ModuleStack.Length > 0;
    }


    // voting stuff below

    uint priorRulesStart = 0;
    void LoadExpectedMapByVoting() {
        throw("Deprecated");
        // votingState = VotingState::NoVoteActive;
        // voteDone_setNextMap = false;
        // while (cast<CSmArenaClient>(GetApp().CurrentPlayground) is null) yield();
        // auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        // while (cp.Map is null || cp.Map.MapInfo is null) yield();
        // if (InExpectedMap() && !SHUTDOWN) {
        //     warn('in expected map; same as last? ' + tostring(mapSameAsLast));
        //     if (!mapSameAsLast) return;
        //     while (UpdateVoteToRestart() && !SHUTDOWN) {
        //         // sleep(50);
        //         yield();
        //     }
        // } else {
        //     while (UpdateVoteToChangeMap() && !SHUTDOWN) {
        //         // sleep(50);
        //         yield();
        //     }
        // }
    }

    VotingState votingState = VotingState::NoVoteActive;

    // return false to break, true if we are not yet done
    bool UpdateVoteToRestart() {
        vote_currRequestType = VoteRequestType::RestartMap;
        // expectedPromptEnd = ExpVoteQuestionEndsWith_GoToNextMap();
        return Vote_UpdateGeneric();
    }

    bool voteDone_setNextMap = false;
    VoteRequestType vote_currRequestType = VoteRequestType::None;
    bool UpdateVoteToChangeMap() {
        // // if we're in the right map then always just exit
        // if (InExpectedMap()) return false;
        if (!voteDone_setNextMap) {
            auto setNextMapLoop = UpdateVote_SetNextMap();
            if (!setNextMapLoop) {
                voteDone_setNextMap = true;
            }
            return true;
        } else {
            auto goToNextLoop = UpdateVote_GoToNextMap();
            if (!goToNextLoop) {
                voteDone_setNextMap = false;
                // wait for map change, need to wait at least 15s for server to change
                uint _timeout = Time::Now + 20000;
                while (Time::Now < _timeout && CurrentlyPlayingOrFinished()) yield();
                while (Time::Now < _timeout && GetApp().CurrentPlayground !is null) yield();
                while (GetApp().CurrentPlayground is null) yield();
            }
            return goToNextLoop;
        }
    }

    bool CurrentlyPlayingOrFinished() {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        if (cmap is null || cmap.UI is null) return false;
        return IsPlayingOrFinished(cmap.UI.UISequence);
    }

    bool UpdateVote_SetNextMap() {
        vote_currRequestType = VoteRequestType::SetNextMap;
        // expectedPromptEnd = ExpVoteQuestionEndsWith_SetNextMapNoCodes();
        return Vote_UpdateGeneric();
    }

    bool UpdateVote_GoToNextMap() {
        vote_currRequestType = VoteRequestType::GoToNextMap;
        // expectedPromptEnd = ExpVoteQuestionEndsWith_GoToNextMap();
        return Vote_UpdateGeneric();
    }

    bool InExpectedMap() {
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        if (cp is null) return false;
        return mapUid == cp.Map.MapInfo.MapUid;
    }

    const string ExpVoteQuestionEndsWith_JumpToMap() {
        return "asks: JumpToMapIdent " + StripFormatCodes(mapName) + "?";
    }

    const string ExpVoteQuestionEndsWith_GoToNextMap() {
        return "asks: Go to next map?";
    }

    const string ExpVoteQuestionEndsWith_RestartMap() {
        return "asks: Restart map?";
    }

    const string ExpVoteQuestionEndsWith_SetNextMapNoCodes() {
        return "asks: SetNextMapIdent " + StripFormatCodes(mapName) + "?";
    }


    bool VoteQuestionIsExpected(CGamePlaygroundClientScriptAPI@ pgcsa) {
        string voteQuestion = StripFormatCodes(pgcsa.Vote_Question).Trim();
        auto matches = voteQuestion.EndsWith(expectedPromptEnd);
#if DEV
        if (!matches) {
            warn("Vote question not as expected. Have: " + StripFormatCodes(pgcsa.Vote_Question) + ", wanted ends with: " + expectedPromptEnd);
        }
#endif
        if (!matches) {
            string asciiVQ;
            string asciiName;
            for (int i = 0; i < voteQuestion.Length; i++) {
                auto item = voteQuestion[i];
                if (item < 128) {
                    asciiVQ += " ";
                    asciiVQ[asciiVQ.Length - 1] = item;
                }
            }
            for (int i = 0; i < expectedPromptEnd.Length; i++) {
                auto item = expectedPromptEnd[i];
                if (item < 128) {
                    asciiName += " ";
                    asciiName[asciiName.Length - 1] = item;
                }
            }
            matches = asciiVQ.EndsWith(asciiName);
            warn("Vote question second go: " + tostring(matches));
            print("processed q: " + asciiVQ);
            print("processed expected tail: " + asciiName);
        }
        return matches;
    }

    void WaitPropagateExpectedVote() {
        sleep(500);
    }

    // call this to reset voting state, e.g., the vote question is wrong
    void ResetVotingState() {
        setExpectedVote("VOTE_QUESTION", "dummy question, reset voting state " + Time::Now);
        votingState = VotingState::WrongVoteActive;
        // wait for server ping
        WaitPropagateExpectedVote();
    }

    /**
     * if NoVoteActive:
     * - start a vote for the right thing
     * - goto: AwaitingRequest
     */
    bool Vote_Initialize(CGamePlaygroundClientScriptAPI@ pgcsa, CGameCtnNetwork@ net) {
        if (pgcsa.Request_IsInProgress) {
            votingState = VotingState::WaitForCallVote;
            return true;
        }
        // no req in progress
        if (net.InCallvote) {
            ResetVotingState();
            return true;
        }
        // no req and no vote in progress
        _CreateVoteRequest(pgcsa);
        votingState = VotingState::WaitForCallVote;
        return true;
    }

    void _CheckVoteQuestionAndUpdateState(CGamePlaygroundClientScriptAPI@ pgcsa) {
        if (pgcsa.Vote_Question.Length == 0) return;
        if (VoteQuestionIsExpected(pgcsa)) {
            votingState = VotingState::CallVoteActive;

        } else {
            warn('question end not as expected: ' + expectedPromptEnd + ' vs ' + StripFormatCodes(pgcsa.Vote_Question));
            votingState = VotingState::WrongVoteActive;
        }
    }

    void _CreateVoteRequest(CGamePlaygroundClientScriptAPI@ pgcsa) {
        if (SHUTDOWN) return;
        warn("Initiating vote of type: " + tostring(vote_currRequestType));
        switch (vote_currRequestType) {
            case VoteRequestType::None: {
                warn("create vote request called with a current request type of None");
                return;
            }
            case VoteRequestType::SetNextMap: {
                pgcsa.RequestSetNextMap(mapUid);
                return;
            }
            case VoteRequestType::RestartMap: {
                pgcsa.RequestRestartMap();
                return;
            }
            case VoteRequestType::GoToNextMap: {
                pgcsa.RequestNextMap();
                return;
            }
        }
    }

    bool Vote_FixWrongPrompt(CGamePlaygroundClientScriptAPI@ pgcsa, CGameCtnNetwork@ net) {
        if (net.InCallvote) {
            if (VoteQuestionIsExpected(pgcsa)) {
                votingState = VotingState::CallVoteActive;
                return true;
            } else if (pgcsa.Vote_CanVote) {
                pgcsa.Vote_Cast(false);
            }
        } else {
            votingState = VotingState::NoVoteActive;
        }
        return true;
    }

    bool Vote_WaitForCallVote(CGamePlaygroundClientScriptAPI@ pgcsa, CGameCtnNetwork@ net) {
        if (pgcsa.Request_IsInProgress)
            return true;
        if (!pgcsa.Request_Success && net.InCallvote) {
            ResetVotingState();
            return true;
        }
        if (net.InCallvote) {
            votingState = VotingState::CallVoteActive;
            string question = StripFormatCodes(pgcsa.Vote_Question);
            setExpectedVote("VOTE_QUESTION", question);
            return Vote_UpdateGeneric();
        }
        if (!pgcsa.Request_Success) {
            votingState = VotingState::CallVoteComplete;
            return true;
        }
        warn("Waiting for call vote but request not in prog");
        votingState = VotingState::NoVoteActive;
        return true;
    }

    int prediction = -1;
    uint lastYes = 0;
    uint lastNo = 0;
    bool Vote_CallVoteActive(CGamePlaygroundClientScriptAPI@ pgcsa, CGameCtnNetwork@ net) {
        if (!net.InCallvote) {
            votingState = VotingState::CallVoteComplete;
            setExpectedVote("VOTE_WAIT", "");
            WaitPropagateExpectedVote();
            return true;
        } else {
            lastYes = net.VoteNbYes;
            lastNo = net.VoteNbNo;
            if (lastYes == 0 && lastNo == 0) {
                prediction = -1;
            } else {
                prediction = lastYes > lastNo ? 1 : 0;
            }
        }
        return true;
    }

    string expectedPromptEnd;
    bool Vote_UpdateGeneric() {
        auto net = GetApp().Network;
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        // if (cp !is null && cp.Arena.Rules.RulesStateEndTime)

        CGamePlaygroundClientScriptAPI@ pgcsa = GetApp().Network.PlaygroundClientScriptAPI;
        if (pgcsa is null || cp is null) return true;

        switch (votingState) {
            case VotingState::NoVoteActive: return Vote_Initialize(pgcsa, net);
            case VotingState::WrongVoteActive: return Vote_FixWrongPrompt(pgcsa, net);
            case VotingState::WaitForCallVote: return Vote_WaitForCallVote(pgcsa, net);
            case VotingState::CallVoteActive: return Vote_CallVoteActive(pgcsa, net);
            case VotingState::CallVoteComplete: {
                votingState = VotingState::NoVoteActive;
                return false;
            }
        }
        warn("Vote_UpdateGeneric did not return after switch on voting state");
        return false;
    }
}


/**
 * Voting
 *
 * We start from an initial state:
 * NoVoteActive
 * CallVoteActive
 * WrongVoteActive
 *
 * if NoVoteActive:
 * - start a vote for the right thing
 * - goto: AwaitingRequest
 *
 * if AwaitingRequest:
 * - if no request yet: wait
 * - when there is a request, is the the right one (regardless of if it is ours)
 *   - if it's the right one, go to CallVoteActive
 *   - otherwise WrongVoteActive
 *
 * if WrongVoteActive:
 *   if can vote, vote no, wait
 *   when no vote is active, go to NoVoteActive
 *
 * if CallVoteActive: (correct vote)
 *   store current state
 *   if can vote, vote yes, wait
 *   if can't vote: wait
 *   if not active anymore: evaluate vote
 *     does last state unambiguously indicate we won? -> CallVoteComplete
 *     if not: wait a bit
 *       after waiting: if ui sequence is still playing, go to //! ???
 *       when done, go to CallVoteComplete / VerifyVoteComplete
 *
 *
 *
 * All States:
 * - NoVoteActive
 * - AwaitingRequest
 * - WrongVoteActive
 * - CallVoteActive
 * - CallVoteComplete
 *
 *
 *
 *
 *
 * Entering map:
 * - RulesStateStartTime set to 4294967295 before round start
 * - RulesStateEndTime set to 4294967295 before round start
 * - both set at the same time
 *
 * Restarting map:
 * - RulesStateStartTime set to 4294967295
 * - RulesStateEndTime set to 4294967295
 * - then both on the same frame when players respawn
 *
 * Ending map (going to new map):
 * - RulesStateStartTime unchanged
 * - RulesStateEndTime set to 4294967295
 * - then cp is null
 * - then entering map
 *
 *
 *
 *
 *
 */


enum VotingState {
    NoVoteActive,
    WaitForCallVote,
    WrongVoteActive,
    CallVoteActive,
    CallVoteComplete
}

enum VoteRequestType {
    None,
    SetNextMap,
    RestartMap,
    GoToNextMap
}



bool IsInWarmUp() {
    auto layer = FindWarmUpUILayer();
    if (layer is null) return false;
    auto frame = layer.LocalPage.GetFirstChild("frame-warm-up");
    if (frame is null) return false;
    // this is visible only when we're in the warmup
    return frame.Visible;
}

CGameUILayer@ FindWarmUpUILayer() {
    auto cmap = GetApp().Network.ClientManiaAppPlayground;
    if (cmap is null) return null;
    auto layer = cmap.UILayers.Length < 20 ? null : cmap.UILayers[18];
    if (layer is null || !layer.ManialinkPageUtf8.StartsWith('\n<manialink name="UIModule_Race_WarmUp"')) {
        for (uint i = 0; i < cmap.UILayers.Length; i++) {
            auto item = cmap.UILayers[i];
            if (item.ManialinkPageUtf8.StartsWith('\n<manialink name="UIModule_Race_WarmUp"')) {
                @layer = item;
                break;
            }
        }
    }
    return layer;
}

CSmScriptPlayer@ FindLocalPlayersInPlaygroundPlayers(CGameCtnApp@ app) {
    auto cp = cast<CGameManiaPlanet>(app).CurrentPlayground;
    for (uint i = 0; i < cp.Players.Length; i++) {
        auto item = cast<CSmPlayer>(cp.Players[i]);
        if (item !is null && item.User.Name == LocalPlayersName) {
            return cast<CSmScriptPlayer>(item.ScriptAPI);
        }
    }
    return null;
}


/**
 *
 * todo: use rules start time -- player start time always set to this, and rules start time is resilient to rejoins
 *
 * rules start/end time mb to detect warmup?
 *
 *
 */
void asdf() {}
