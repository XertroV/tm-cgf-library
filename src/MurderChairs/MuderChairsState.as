/**
 * The idea is similar to the game 'Murder' combined with musical chairs.
 *
 * Murder is where you get a plastic knife with someone's name on it,
 * and by touching them with the knife you eliminate them from the game.
 * You then get their knife, and their target becomes your next target.
 *
 * Musical chairs is a game where you start with 1 chair per player.
 * When the music starts playing, players get up and being moving in a
 * circle around the chairs, and one chair is removed. When the music
 * stops, players need to sit down as fast as possible and whoever is
 * left standing is eliminated.
 *
 * Murder Chairs:
 * - decide on player order (1 list, and connect the ends to make one big loop)
 * - start with 1 random map per player
 * - when player beats the map (any time, or condition mb) they move on to the next map
 * - ANY PLAYERS 'ahead' of you (joined the map before you) are eliminated when you finish a map
 * - any map that is not currently occupied by a player is removed
 * - players continue until only 1 player remains
 *
 * Murderous Chairs
 *
*/

/**
* players can be in the same map
*/
class MurderChairsState {
    Game::Client@ client;

    MCMap@[] maps;
    MCPlayer@[] players;
    bool IsTeams;

    MCGameEvent@[] eventLog;
    MCGameEvent@[] activeEvents;

    bool IsGameOver = false;

    MCPlayer@ myPlayer;

    MurderChairsState(Game::Client@ client) {
        @this.client = client;
    }

    /**
     * core game loop:
     * - find which map you're in
     * - join map
     * - wait to finish
     *   -> publish time and wait for state to update
     *   -> state updating should detect that we're not on the right map anymore, so switch maps
     * - if we notice that .isAlive == false at any point, show a message to the player that they're eliminated but don't quit the map.
     *   - let them keep playing and/or choose any of the random maps to play?
     *   - interaction from audience after KO?
     *
     * hmm problem (for future): if you have a 1v1 with evenly matched players, it could take a while to resolve.
     * option: team win condition, not just player win con; mb when a player finishes, instead of KOing team mates, they all advance
     */

    void OnPlayerFinish(const string &in uid, int time, float msgTimestamp) {
        bool didDNF = time > DNF_TEST;

        if (didDNF) {
            for (uint i = 0; i < players.Length; i++) {
                auto player = players[i];
                if (player.uid == uid) {
                    player.isAlive = false;
                    return;
                }
            }
            return;
        }

        // todo: we could check for map removal here, too.

        // implicitly, players are in order -- they'll only ever KO players in front of them (bc if they didn't, they'd have been knocked out)
        // but we need to check the start of the array too, incase the KO wraps around
        // also, we still want to check the map entry time in case all players are on the same map

        MCPlayer@[] earlyPlayersOnSameMap;
        int earlyMapNumber = players[0].mapNumber;
        bool earlyPlayersDone = false;
        MCPlayer@ thisPlayer = null;
        int thisPlayersMap = -1;
        for (uint i = 0; i < players.Length; i++) {
            auto player = players[i];
            if (!earlyPlayersDone) {
                if (player.mapNumber == earlyMapNumber) earlyPlayersOnSameMap.InsertLast(player);
                else earlyPlayersDone = true;
            }
            if (player.uid == uid) {
                @thisPlayer = player;
                thisPlayersMap = thisPlayer.mapNumber;
            } else if (thisPlayer !is null) {
                if (DidPlayerKOPlayer(thisPlayer, player))
                    MarkPlayerKOdBy(player, thisPlayer);
                else if (ShouldAdvanceTeamMate(thisPlayer, player))
                    AdvanceMap(player, msgTimestamp);
                else break;
            }
        }
        if (thisPlayer is null || thisPlayersMap == -1) {
            // ! error, did not find player.
            error("OnPlayerFinish Did not find player.");
            return;
        }
        if (thisPlayersMap == earlyMapNumber) {
            for (uint i = 0; i < earlyPlayersOnSameMap.Length; i++) {
                auto player = earlyPlayersOnSameMap[i];
                if (DidPlayerKOPlayer(thisPlayer, player))
                    MarkPlayerKOdBy(player, thisPlayer);
                else if (ShouldAdvanceTeamMate(thisPlayer, player))
                    AdvanceMap(player, msgTimestamp);
            }
        }
        AdvanceMap(thisPlayer, msgTimestamp);
        CheckGameOver();
        CheckRemoveAMap(msgTimestamp, thisPlayersMap);
    }

    void CheckGameOver() {
        uint aliveCount = 0;
        int[] aliveTeams;
        for (uint i = 0; i < players.Length; i++) {
            auto player = players[i];
            if (player.isAlive) aliveCount++;
            if (!IsTeams && aliveCount > 1) return;
            if (aliveTeams.Find(player.team) < 0) aliveTeams.InsertLast(player.team);
            if (IsTeams && aliveTeams.Length > 1) return;
        }
        IsGameOver = true;
    }

    float lastMapRemovedAt = 0;
    float waitTimeBetweenRemoval = 30.;

    void CheckRemoveAMap(float msgTimestamp, int recentMapNumber) {
        if (IsGameOver) return;
        if (msgTimestamp - lastMapRemovedAt < waitTimeBetweenRemoval) return;
        // check for an empty map
        auto tmpMapNum = recentMapNumber;
        auto map = maps[tmpMapNum];
        auto nMaps = maps.Length;
        while (!map.isActive || map.nPlayers != 0) {
            tmpMapNum = (tmpMapNum + 1) % nMaps;
            if (tmpMapNum == recentMapNumber) {
                // couldn't find a map to remove
                return;
            }
            @map = maps[tmpMapNum];
        }
        lastMapRemovedAt = msgTimestamp;
        map.isActive = false;
        OnMapRemoved(tmpMapNum);
    }

    void OnMapRemoved(int mapNumber) {
        // todo: game log
        AddGameEvent(MCEventMapRemoved(maps[mapNumber], mapNumber));
    }

    bool ShouldAdvanceTeamMate(MCPlayer@ finishingPlayer, MCPlayer@ otherPlayer) {
        return IsTeams && finishingPlayer.team == otherPlayer.team && finishingPlayer.mapNumber == otherPlayer.mapNumber;
    }

    bool DidPlayerKOPlayer(MCPlayer@ finishingPlayer, MCPlayer@ otherPlayer) {
        if (finishingPlayer is null || otherPlayer is null) return false;
        // player.mapNumber == thisPlayersMap && player.enteredMapAt <= thisPlayer.enteredMapAt
        return finishingPlayer.mapNumber == otherPlayer.mapNumber
            && finishingPlayer.enteredMapAt >= otherPlayer.enteredMapAt
            && (!IsTeams ^^ (finishingPlayer.team != otherPlayer.team));
    }

    void MarkPlayerKOdBy(MCPlayer@ playerOut, MCPlayer@ killer) {
        playerOut.isAlive = false;
        @playerOut.killedBy = killer;
        OnPlayerKOd(playerOut, killer);
    }

    void OnPlayerKOd(MCPlayer@ playerOut, MCPlayer@ killer) {
        // todo: game log
        AddGameEvent(MCEventKO(playerOut, killer));
    }

    void AdvanceMap(MCPlayer@ player, float msgTimestamp) {
        if (maps[player.mapNumber].nPlayers == 0) {
            warn("[AdvanceMap] map number " + player.mapNumber + " has no players!");
        } else {
            maps[player.mapNumber].nPlayers -= 1;
        }
        auto currMap = player.mapNumber + 1;
        for (uint i = currMap; i < maps.Length; i++) {
            auto map = maps[i];
            if (map.isActive) {
                SetMapFor(player, i, msgTimestamp);
                return;
            }
        }
        // we didn't find an active map, so loop back to start of list
        for (uint i = 0; i < maps.Length; i++) {
            auto map = maps[i];
            if (map.isActive) {
                SetMapFor(player, i, msgTimestamp);
                return;
            }
        }
        throw('Should be impossible, no maps left!');
    }

    void SetMapFor(MCPlayer@ player, int mapNumber, float msgTimestamp) {
        player.mapNumber = mapNumber;
        player.enteredMapAt = msgTimestamp;
        player.mapSeq++;
        maps[mapNumber].nPlayers += 1;
    }

    //

    void AddGameEvent(MCGameEvent@ event) {
        eventLog.InsertLast(event);
        activeEvents.InsertLast(event);
    }
}

/**
 * one per player
 */
class MCPlayer {
    string uid;
    string name;
    bool isAlive = true;
    uint mapNumber = 0;
    float enteredMapAt;
    int team;
    uint mapSeq = 0;
    MCPlayer@ killedBy = null;
}

/**
 * keep one of these for each map
 */
class MCMap {
    int TrackID;
    uint nPlayers = 1;
    bool isActive = true;
    string name;
}

float BaseFontHeight {
    get {
        return float(Draw::GetHeight()) / 1080. * 24.;
    }
}

float EventLogSpacing {
    get {
        return BaseFontHeight / 4.;
    }
}

// purpose: keep an array of these. they are used to draw UI status elements.
// call .RenderUpdate(float dt, vec2 pos) and when it returns true, it's done
class MCGameEvent {
    vec4 col = vec4(1, 1, 1, 1);
    string msg = "undefined";
    float animDuration = 5.0;
    float currTime = 0.0;
    float t = 0.0;
    float baseFontSize = BaseFontHeight;

    bool RenderUpdate(float dt, vec2 pos) {
        currTime += dt;
        t = currTime / animDuration;
        if (t > 1.) return true;
        float alpha = Math::Clamp(5. - t * 5., 0., 1.);
        float fs = baseFontSize * Math::Clamp((t + .2), 1, 1.2);
        nvg::FontSize(fs);
        nvg::FillColor(col * vec4(1, 1, 1, 0) + vec4(0, 0, 0, alpha));
        nvg::Text(pos, msg);
        return false;
    }
}


class MCEventKO : MCGameEvent {
    MCEventKO(MCPlayer@ playerOut, MCPlayer@ killer) {
        // todo
        msg = killer.name + " knocked out " + playerOut.name;
    }
}

class MCEventMapRemoved : MCGameEvent {
    MCEventMapRemoved(MCMap@ map, uint mapNumber) {
        // todo
        msg = "Map #"+mapNumber+" removed. (" + map.name + ")";
    }
}
