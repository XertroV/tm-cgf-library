#if DEV || UNIT_TEST

bool QUIET_TESTS = true;

void log_test(const string &in msg) {
    if (QUIET_TESTS) return;
    print(msg);
}

void TestScoring() {
    for (uint i = 0; i < 10; i++) {
        yield();
        Test_Teams_Scoring();
    }
}

void Test_Teams_Scoring() {
    auto cr = ChallengeResultState();
    auto teams = GenTeams(3, 3);
    auto challenger = RandomTeam();
    auto defender = TTGSquareState(-(challenger - 1));
    bool team1Advantage = RandomBool();
    int t1p1Time = team1Advantage ? 100 : 111;
    cr.Activate(1, 1, challenger, TTGGameState::InClaim, teams, TTGMode::Teams);
    cr.SetPlayersTime(teams[0][0], t1p1Time, TTGSquareState::Player1);
    cr.SetPlayersTime(teams[0][1], 222, TTGSquareState::Player1);
    cr.SetPlayersTime(teams[0][2], team1Advantage ? 999 : DNF_TIME, TTGSquareState::Player1);
    cr.SetPlayersTime(teams[1][0], 111, TTGSquareState::Player2);
    cr.SetPlayersTime(teams[1][1], 200, TTGSquareState::Player2);
    cr.SetPlayersTime(teams[1][2], DNF_TIME, TTGSquareState::Player2);
    // leaders order based on which is defender, then t2p2, then t1p2, then p3 based on defender
    // if (team1Advantage && challenger == 0) {
    //     assert(cr.teamsRanking[0].uid == teams[challenger][0], '1st place');
    //     assert(cr.teamsRanking[1].uid == teams[defender][0], '2nd place');
    // } else {
    assert(cr.teamsRanking[0].uid == teams[team1Advantage ? 0 : defender][0], '1st place');
    assert(cr.teamsRanking[1].uid == teams[team1Advantage ? 1 : challenger][0], '2nd place');
    assert(cr.teamsRanking[2].uid == teams[1][1], '3rd place');
    assert(cr.teamsRanking[3].uid == teams[0][1], '4th place');
    assert(cr.teamsRanking[4].uid == teams[team1Advantage ? 0 : defender][2], '5th place');
    assert(cr.teamsRanking[5].uid == teams[team1Advantage ? 1 : challenger][2], '6th place');
    log_test("\\$0d5 -- RAN TEST: Scoring -- ");
    log_test("winner: " + cr.Winner);
    log_test("challenger: " + cr.challenger);
    log_test("defender: " + cr.defender);
    for (uint i = 0; i < cr.teamsRanking.Length; i++) {
        auto ur = cr.teamsRanking[i];
        log_test('Rank: ' + (i + 1) + ". " + ur.uid + ": " + ur.time);
    }
}

void assert(bool cond, const string &in msg) {
    if (!cond) error('Test failed condition: ' + msg);
}

TTGSquareState RandomTeam() {
    return TTGSquareState(Math::Rand(0, 2));
}

bool RandomBool() {
    return 0 == Math::Rand(0, 2);
    // float n = Math::Rand(0.0, 100.0);
    // return n < 50.0;
}


string[][]@ GenTeams(int t1_n = 3, int t2_n = 3) {
    string[][] teams = {{}, {}};
    for (uint i = 0; i < t1_n; i++) teams[0].InsertLast("t1-" + i);
    for (uint i = 0; i < t2_n; i++) teams[1].InsertLast("t2-" + i);
    return teams;
}


#else
void TestScoring() {}
#endif
