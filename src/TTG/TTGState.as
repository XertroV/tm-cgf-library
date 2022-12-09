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
    bool claimed;
    bool seen;
    TTGSquareState owner = TTGSquareState::Unclaimed;

    SquareState() {
        Reset();
    }

    void Reset() {
        claimed = false;
        seen = false;
        owner = TTGSquareState::Unclaimed;
    }
}

class TicTacGoState {
    TTGMode mode = TTGMode::Standard;
    TTGGameState state = TTGGameState::PreStart;

    SquareState[][] boardState;
    // bool[][] boardMapKnown;

    TTGSquareState MyTeamLeader;
    TTGSquareState TheirTeamLeader;
    TTGSquareState ActiveLeader;
    TTGSquareState WinningLeader;
    int2[] WinningSquares;

    ChallengeResultState@ challengeResult = ChallengeResultState();
    TTGGameEvent@[] gameLog;
    uint turnCounter = 0;

    bool opt_EnableRecords = false;

    TicTacGoState() {
        Reset();
    }

    void Reset() {
        mode = TTGMode::Standard;
        state = TTGGameState::PreStart;
        turnCounter = 0;
        gameLog.Resize(0);
        challengeResult.Reset();

        boardState.Resize(3);
        for (uint i = 0; i < 3; i++) {
            boardState[i].Resize(3);
            for (uint j = 0; j < 3; j++) {
                boardState[i][j].Reset();
            }
        }
    }

    void LoadFromGameOpts(Json::Value@ game_opts) {
        Reset();
        if (game_opts.GetType() != Json::Type::Object) {
            log_warn("LoadFromGameOpts: game_opts is not a json object");
            return;
        }
        opt_EnableRecords = GetGameOptBool(game_opts, 'enable_records', false);
        // mode = GetGameOptMode(game_opts);
        mode = TTGMode(GetGameOptInt(game_opts, 'mode', int(TTGMode::Standard)));
    }

    bool GetGameOptBool(Json::Value@ opts, const string &in key, bool def) {
        try {
            return opts[key];
        } catch {
            return def;
        }
    }

    int GetGameOptInt(Json::Value@ opts, const string &in key, int def) {
        try {
            return opts[key];
        } catch {
            return def;
        }
    }

    // TTGMode GetGameOptMode(Json::Value@ opts) {
    //     try {
    //         return TTGMode(int(opts['mode']));
    //     } catch {
    //         return TTGMode::Standard;
    //     }
    // }

    TTGSquareState get_InactiveLeader() {
        return ActiveLeader == TTGSquareState::Player1 ? TTGSquareState::Player2 : TTGSquareState::Player1;
    }

    bool get_IsSinglePlayer() {
        return mode == TTGMode::SinglePlayer;
    }

    bool get_IsStandard() {
        return mode == TTGMode::Standard;
    }

    bool get_IsTeams() {
        return mode == TTGMode::Teams;
    }

    bool get_IsBattleMode() {
        return mode == TTGMode::BattleMode;
    }

    bool IsValidMove() const {
        return false;
    }
}
