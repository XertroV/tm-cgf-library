funcdef void ChallengeRunReport(int duration);

class ChallengeRun {
    // relative to Time::Now to avoid pause menu strats
    int challengeStartTime = -1;
    int playerInitStartTime = -1;
    int lastPlayerStartTime = -1;
    int challengeEndTime = -1;
    int challengeScreenTimeout = -1;
    int currGameTime = -1;
    int currPeriod = 15;  // frame time
    bool challengeRunActive = false;
    bool disableLaunchMapBtn = false;
    bool hideChallengeWindowInServer = false;
    uint challengeEndedAt;
    bool showForceEndPrompt = false;
    bool shouldExitChallenge = false;
    uint shouldExitChallengeTime = DNF_TIME;
    bool serverChallengeInExpectedMap = false;
    uint lastSpamNo = 0;
    int initNbGhosts = 0;
    int duration = -1;
    bool opt_EnableRecords = false;
    int opt_AutoDNF_ms = -1;
    CSmScriptPlayer@ player;
    ChallengeResultState@ challengeResult = ChallengeResultState();

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

    ChallengeRunReport@ reportFunc;

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
            ChallengeRunReport@ reportFunc,
            int opt_AutoDNF_ms = -1,
            bool opt_EnableRecords = false
        ) {
        this.initialized = true;

        this.opt_EnableRecords = opt_EnableRecords;
        this.opt_AutoDNF_ms = opt_AutoDNF_ms;

        if (reportFunc is null) throw('report func null!');
        @this.reportFunc = reportFunc;

        this.loadingScreenTop = loadingScreenTop;
        this.loadingScreenBottom = loadingScreenBottom;

        this.trackID = trackID;
        this.mapUid = mapUid;
        this.mapName = mapName;
        this.mapSameAsLast = mapSameAsLast;
        this.runInServer = runInServer;
    }

    void EnsureInit() {
        yield();
        if (!initialized) {
            throw("You must call .Initialize immediately after instantiating a ChallengeRun");
        }
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

    // terminates when we are in the intro
    void OnReady_WaitForPlayers() {
        while (GetApp().CurrentPlayground is null) yield();
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        while (cp !is null && cp.Players.Length < 1) yield();
        // auto player = cast<CSmScriptPlayer>(cast<CSmPlayer>(cp.Players[0]).ScriptAPI);
        // cmap never null
        while (cp !is null && cmap.UI is null) yield();
    }

    void OnReady_WaitForUI() {
        auto cp = cast<CSmArenaClient>(GetApp().CurrentPlayground);
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        while (cp !is null && cmap !is null && cmap.UI is null) yield();
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
        SetLoadingScreen();
    }

    void Activate() {
        runActive = true;
        // load map / join server
        // wait for map, currPG to load
        // in server: change map if need be
        Activate_LoadChallengeMapAsync();
    }

    void PostActivate() {
        OnReady_WaitForPlayers();
        OnReady_WaitForUI();
        OnReady_WaitForUISequences();

        // wait for players, ui configs
        // wait for intro sequence

        // wait for playing sequence
        // wait for player StartTime
    }

    void PreMain() {
        // records hide/show
        HideGameUI::opt_EnableRecords = opt_EnableRecords;
        startnew(HideGameUI::OnMapLoad);

        // init track ghost, etc
        initNbGhosts = GetCurrNbGhosts();

        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        if (cmap is null) return;
        @player = FindLocalPlayersInPlaygroundPlayers(GetApp());

        // set start time
        currGameTime = cmap.Playground.GameTime;
        challengeStartTime = Time::Now + (player.StartTime - currGameTime);
        playerInitStartTime = player.StartTime;
        lastPlayerStartTime = player.StartTime;
        // while (player.CurrentRaceTime > 0) yield(); // wait for current race time to go negative
        if (challengeStartTime < int(Time::Now)) {
            warn("challengeStartTime is in the past; now - start = " + (int(Time::Now) - challengeStartTime) + ".");
            // the timer should always start at -1.5s, so set it 1.5s in the future
            // challengeStartTime = Time::Now + 1500;
        }

        log_info("Set challenge start time: " + challengeStartTime);
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

    // for voting in server mode
    void Main_Pre_Check_Finish() {
        return;
    }

    // return true to continue, false to break
    bool UpdateMain() {
        // **** CHECK VOTES
        Main_Pre_Check_Finish();
        // **** CHECK FINISH
        // - check for finish
        // -- get time from ghost
        // -- set vars
        // -- report result
        if (!hasFinished && Main_Check_Finish()) {
            hasFinished = true;
            while (initNbGhosts == GetCurrNbGhosts()) yield();
            auto runTime = GetMostRecentGhostTime();
            auto endTime = lastPlayerStartTime + runTime;
            duration = endTime - playerInitStartTime;
            challengeEndTime = challengeStartTime + duration;
            // report result
            ReportChallengeResult(duration);
        }
        // **** UPDATE NOT FINISHED
        // - if not finished
        // -- update duration, start time, nb ghosts, opponent time, time left (if dnf), shouldDnf flag
        int oppTime = 0;
        int timeLeft = DNF_TEST;
        bool shouldDnf = false;
        if (!hasFinished) {
            duration = Time::Now - challengeStartTime;
            lastPlayerStartTime = player.StartTime;
            initNbGhosts = GetCurrNbGhosts();
            oppTime = challengeResult.ranking.Length > 0 ? challengeResult.ranking[0].time : DNF_TIME;
            timeLeft = oppTime + opt_AutoDNF_ms - duration;
            shouldDnf = opt_AutoDNF_ms > 0 && timeLeft <= 0;
        }
        // if the challenge is resolved (e.g., via force ending) then we want to exit out
        // ~~also if we already have a result~~ leave players in the map while other ppl haven't finished yet
        shouldExitChallenge = challengeResult.IsResolved;

        // **** CHECK EXIT LOOP
        // - check if challenge resolved, or should DNF, or null pg, etc
        // -- maybe report dnf time
        // -- set exit challenge time
        // -- break loop
        if (Main_Check_ShouldExit()) {
            log_trace('should dnf, or exit, or player already did.');
            if (shouldDnf) {
                log_warn("shouldDnf. time left: " + timeLeft + "; oppTime: " + oppTime + ", duration=" + duration);
            }
            // don't report a time if the challenge is resolved b/c it's an invalid move
            if (!shouldExitChallenge && !hasFinished)
                ReportChallengeResult(DNF_TIME); // more than 24 hrs, just
            // if we are still in the map we want to let hte user know before we exit
            if (shouldExitChallenge) {
                shouldExitChallengeTime = Time::Now + 3000;
                AwaitShouldExitTimeOrMapLeft();
            }
            // player quit (or auto DNF)
            warn("Map left. Either: player quit, autodnf, or challenge resolved");
            return false;
        }
        // ** UPDATE
        // - update game time, period, etc
        currGameTime = GetApp().Network.ClientManiaAppPlayground.Playground.GameTime;
        if (!hasFinished)
            challengeEndTime = Time::Now;
        currPeriod = GetApp().Network.PlaygroundInterfaceScriptHandler.Period;
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
        PreActivate();
        Activate();
        PostActivate();
        // ** CHALLENGE READY
        if (PreMain_CheckExit()) return;
        // ** Start
        PreMain();
        while (UpdateMain()) yield();
        // ** END
        PostMain();
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
        throw('todo');
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

    void Activate_LoadChallengeMapAsync() override {
        auto app = GetApp();
        while (app.CurrentPlayground is null) yield();
        auto cp = cast<CSmArenaClient>(app.CurrentPlayground);
        while (cp.Map is null) yield();
        while (app.Network.ClientManiaAppPlayground is null) yield();
        // warn('setting challenge run active');
        challengeRunActive = true;
        priorRulesStart = cp.Arena.Rules.RulesStateStartTime;
        LoadExpectedMapByVoting();
    }

    void OnReady_WaitForUISequences() override {
        auto app = GetApp();
        auto cmap = app.Network.ClientManiaAppPlayground;
        while (cmap.UILayers.Length < 15) yield();
        while (cmap !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        sleep(100);
        while (cmap !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        while (IsInWarmUp()) yield();
        sleep(100);
        while (cmap !is null && cmap.UI.UISequence != CGamePlaygroundUIConfig::EUISequence::Playing) yield();
        hideChallengeWindowInServer = true;
    }


    void Main_Pre_Check_Finish() override {

    }

    bool Main_Check_ShouldExit() override {
        return GetApp().CurrentPlayground is null && GetApp().Switcher.ModuleStack.Length > 0;
    }


    // voting stuff below

    uint priorRulesStart = 0;
    void LoadExpectedMapByVoting() {
        if (InExpectedMap()) {
            if (!mapSameAsLast) return;
            while (UpdateVoteToRestart()) {
                sleep(50);
            }
        } else {
            while (UpdateVoteToChangeMap()) {
                sleep(50);
            }
        }
    }

    VotingState votingState = VotingState::NoVoteActive;

    // return false to break, true if we are not yet done
    bool UpdateVoteToRestart() {
        vote_currRequestType = VoteRequestType::RestartMap;
        expectedPromptEnd = ExpVoteQuestionEndsWith_GoToNextMap();
        return Vote_UpdateGeneric();
    }

    bool voteDone_setNextMap = false;
    VoteRequestType vote_currRequestType = VoteRequestType::None;
    bool UpdateVoteToChangeMap() {
        // if we're in the right map then always just exit
        if (InExpectedMap()) return false;
        if (!voteDone_setNextMap) {
            return UpdateVote_SetNextMap();
        } else {
            return UpdateVote_GoToNextMap();
        }
    }

    bool UpdateVote_SetNextMap() {
        vote_currRequestType = VoteRequestType::SetNextMap;
        expectedPromptEnd = ExpVoteQuestionEndsWith_SetNextMapNoCodes();
        return Vote_UpdateGeneric();
    }

    bool UpdateVote_GoToNextMap() {
        vote_currRequestType = VoteRequestType::GoToNextMap;
        expectedPromptEnd = ExpVoteQuestionEndsWith_GoToNextMap();
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
        auto matches = StripFormatCodes(pgcsa.Vote_Question).EndsWith(expectedPromptEnd);
#if DEV
        if (!matches) {
            warn("Vote question not as expected. Have: " + StripFormatCodes(pgcsa.Vote_Question) + ", wanted ends with: " + expectedPromptEnd);
        }
#endif
        return matches;
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
            if (pgcsa.Vote_Question.Length == 0) return true;
            _CheckVoteQuestionAndUpdateState(pgcsa);
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
        if (net.InCallvote) {
            _CheckVoteQuestionAndUpdateState(pgcsa);
            return true;
        }
        if (pgcsa.Request_IsInProgress)
            return true;
        warn("Waiting for call vote but request not in prog");
        return true;
    }

    int prediction = -1;
    uint lastYes = 0;
    uint lastNo = 0;
    bool Vote_CallVoteActive(CGamePlaygroundClientScriptAPI@ pgcsa, CGameCtnNetwork@ net) {
        if (!VoteQuestionIsExpected(pgcsa)) {
            _CheckVoteQuestionAndUpdateState(pgcsa);
        } else {
            if (net.InCallvote) {
                if (pgcsa.Vote_CanVote) {
                    pgcsa.Vote_Cast(true);
                }
                lastYes = net.VoteNbYes;
                lastNo = net.VoteNbNo;
                if (lastYes == 0 && lastNo == 0) {
                    prediction = -1;
                } else {
                    prediction = lastYes > lastNo ? 1 : 0;
                }
            } else {
                // we had an expected vote and it's done, assume it passed and let outside code monitor it.
                votingState = VotingState::CallVoteComplete;
                return true;
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
            case VotingState::CallVoteComplete: return false;
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
