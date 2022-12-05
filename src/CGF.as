namespace Game {
    const string StorageFileTemplate = IO::FromStorageFolder("account_|CLIENTNAME|.json");

    enum Scope {
        MainLobby, InGameLobby, InRoom, InGame
    }

    enum ClientState {
        Uninitialized, Connecting, Connected, Disconnected, DoNotReconnect, TimedOut, Shutdown
    }

    enum GameState {
        None, NotStarted, StartingSoon, Started
    }

    class Client : CGF::Client {
        Net::Socket@ socket = Net::Socket();
        string host;
        uint16 port;

        string name;
        string fileName;
        bool accountExists;
        string clientUid;
        ClientState state = ClientState::Uninitialized;
        bool loggedIn = false;
        int connectedAt;

        dictionary currentPlayers;
        dictionary readyStatus;
        uint readyCount;
        string[] currAdmins;
        string[] currMods;
        string[][] currTeams;
        dictionary uidToTeamNb;
        // timestamp of game start
        float gameStartTS = -1.;
        // game start relative to `Time::Now`
        float gameStartTime = -1.;

        Json::Value@ latestServerInfo;
        // Json::Value@ lobbyInfo;
        LobbyInfo@ lobbyInfo;
        RoomInfo@ roomInfo;
        GameInfoFull@ gameInfoFull;
        Json::Value@ mapsList;

        Scope currScope = Scope::MainLobby;
        Scope priorScope = Scope::MainLobby;
        string scopeName;

        Json::Value@[] globalChat = array<Json::Value@>(100);
        uint globalChatNextIx = 0;
        Json::Value@[] lobbyChat = array<Json::Value@>(100);
        uint lobbyChatNextIx = 0;
        Json::Value@[] roomChat = array<Json::Value@>(100);
        uint roomChatNextIx = 0;
        Json::Value@[] mapChat = array<Json::Value@>(100);
        uint mapChatNextIx = 0;

        Json::Value@ pendingMsgs;
        dictionary messageHandlers;

        Engine@ gameEngine;
        protected bool _GameReplayInProgress;
        protected int _GameReplayNbMsgs;

        /**
         *
         *  dP""b8  dP"Yb  88b 88 88b 88 888888  dP""b8 888888 88  dP"Yb  88b 88
         * dP   `" dP   Yb 88Yb88 88Yb88 88__   dP   `"   88   88 dP   Yb 88Yb88
         * Yb      Yb   dP 88 Y88 88 Y88 88""   Yb        88   88 Yb   dP 88 Y88
         *  YboodP  YbodP  88  Y8 88  Y8 888888  YboodP   88   88  YbodP  88  Y8
         *
         * CONNECTION
         *
         */

        // alternative user name is the optional param -- for testing
        Client(const string &in _name = "") {
            host = S_LocalDev ? "localhost" : S_Host;
            port = S_Port;
            AddMessageHandler("SEND_CHAT", CGF::MessageHandler(MsgHandler_Chat));
            AddMessageHandler("ENTERED_LOBBY", CGF::MessageHandler(MsgHandler_LobbyInfo));
            AddMessageHandler("LOBBY_INFO", CGF::MessageHandler(MsgHandler_LobbyInfo));
            AddMessageHandler("ROOM_INFO", CGF::MessageHandler(MsgHandler_RoomInfo));
            AddMessageHandler("NEW_ROOM", CGF::MessageHandler(MsgHandler_NewRoom));
            AddMessageHandler("ROOM_UPDATE", CGF::MessageHandler(MsgHandler_RoomUpdate));
            AddMessageHandler("PLAYER_LEFT", CGF::MessageHandler(MsgHandler_PlayerEvent));
            AddMessageHandler("PLAYER_JOINED", CGF::MessageHandler(MsgHandler_PlayerEvent));
            AddMessageHandler("PLAYER_LIST", CGF::MessageHandler(MsgHandler_PlayerEvent));
            AddMessageHandler("ADMIN_MOD_STATUS", CGF::MessageHandler(MsgHandler_AdminModStatus));
            AddMessageHandler("LIST_TEAMS", CGF::MessageHandler(MsgHandler_TeamsEvent));
            AddMessageHandler("PLAYER_JOINED_TEAM", CGF::MessageHandler(MsgHandler_TeamsEvent));
            AddMessageHandler("PLAYER_READY", CGF::MessageHandler(MsgHandler_ReadyEvent));
            AddMessageHandler("LIST_READY_STATUS", CGF::MessageHandler(MsgHandler_ReadyEvent));
            AddMessageHandler("GAME_STARTING_AT", CGF::MessageHandler(MsgHandler_GameStartHandler));
            AddMessageHandler("GAME_START_ABORT", CGF::MessageHandler(MsgHandler_GameStartHandler));
            AddMessageHandler("GAME_REPLAY_START", CGF::MessageHandler(MsgHandler_GameReplayHandler));
            AddMessageHandler("GAME_REPLAY_END", CGF::MessageHandler(MsgHandler_GameReplayHandler));
            //
            AddMessageHandler("GAME_INFO", CGF::MessageHandler(MsgHandler_GameInfo));
            AddMessageHandler("GAME_INFO_FULL", CGF::MessageHandler(MsgHandler_GameInfoFull));
            AddMessageHandler("MAPS_INFO_FULL", CGF::MessageHandler(MsgHandler_MapsInfoFull));

            name = _name.Length == 0 ? LocalPlayersName : _name;
            fileName = StorageFileTemplate.Replace("|CLIENTNAME|", name);
            accountExists = IO::FileExists(fileName);
            OnChangedScope();
            Connect();
            while (!IsConnected) {
                warn("Attempting reconnect during init in 1s");
                sleep(1000);
                Connect();
            }
            if (IsConnected) {
                SendChat("Hi I'm " + name);
            }
            startnew(CoroutineFunc(ReconnectIfPossible));
        }

        ~Client() {
            Disconnect();
        }

        void Shutdown() {
            Disconnect();
            state = ClientState::Shutdown;
        }

        void ReconnectIfPossible() {
            while (!IsDoNotReconnect && !IsShutdown) {
                yield();
                if (IsShutdown || IsDoNotReconnect) return;
                if (!socket.CanWrite() && !socket.CanRead() && socket.Available() == 0) state = ClientState::Disconnected;
                if (IsDisconnected || IsTimedOut) {
                    warn("[ReconnectIfPossible] in 0.5s");
                    sleep(500);  // sleep .5s to avoid trying again too soon
                    Reconnect();
                }
            }
        }

        void Connect(uint timeout = 5000) {
            if (IsDoNotReconnect || IsShutdown) {
                warn("Refusing to reconnect since client state is DoNotReconnect or Shutdown");
                return;
            }
            state = ClientState::Connecting;
            // we must initialize a new socket here b/c otherwise we'll hang on reuse (i.e., via reconnect); fix is to restart the server (wtf?)
            @socket = Net::Socket();
            uint startTime = Time::Now;
            uint timeoutAt = startTime + timeout;
            try {
                socket.Connect(host, port);
            } catch {
                warn("Failed to init connection to CGF server: " + getExceptionInfo());
            }
            while (Time::Now < timeoutAt && !socket.CanWrite() && !socket.CanRead()) {
                yield();
            }
            if (Time::Now >= timeoutAt) {
                warn("Timeout connecting to " + host + ":" + port);
                this.Disconnect();
                state = ClientState::TimedOut;
            } else {
                warn("Connected in " + (Time::Now - startTime) + " ms");
                state = ClientState::Connected;
            }
            if (IsConnected) {
                connectedAt = Time::Now;
                OnConnected();
            }
        }

        int get_ConnectionDuration() { return IsConnected ? (Time::Now - connectedAt) : 0; }
        bool get_IsConnected() { return state == ClientState::Connected; }
        bool get_IsConnecting() { return state == ClientState::Connecting; }
        bool get_IsDisconnected() { return state == ClientState::Disconnected; }
        bool get_IsTimedOut() { return state == ClientState::TimedOut; }
        bool get_IsDoNotReconnect() { return state == ClientState::DoNotReconnect; }
        bool get_IsShutdown() { return state == ClientState::Shutdown; }
        bool get_IsReconnectable() { return IsDisconnected || IsTimedOut; }

        void Reconnect(uint timeout = 5000) {
            if (!IsDisconnected && !IsTimedOut) return;
            warn("Attempting reconnect...");
            Connect(timeout);
        }

        void OnConnected() {
            priorScope = currScope;
            // expect server version
            auto msg = ReadMessage();
            if (msg is null) {
                warn("OnConnected got null msg immediately.");
                this.Disconnect();
                return;
            }
            @latestServerInfo = msg["server"];
            string ver = string(latestServerInfo["version"]);
            int nbClients = int(latestServerInfo['n_clients']);
            print("Connected. Server version: " + ver);
            NotifyInfo("Connected.\nServer Version: " + ver + "\nCurrent Players: " + (nbClients + 1));
            // login if possible
            if (accountExists) {
                auto deets = Json::FromFile(fileName);
                clientUid = deets['uid'];
                if (!Login(deets)) {
                    NotifyError("Failed to log in :(");
                    IO::Move(fileName, fileName + "_bak_" + Time::Stamp);
                    warn('LoginFailed');
                    accountExists = false;
                } else {
                    NotifyInfo("Logged in!");
                    loggedIn = true;
                }
            }
            if (!accountExists) {
                // otherwise register a new account
                auto resp = RegisterAccount();
                if (resp is null || resp.GetType() == Json::Type::Null) {
                    this.Disconnect();
                    return;
                }
                else if ("REGISTERED" == resp['type']) {
                    accountExists = true;
                    Json::ToFile(fileName, resp['payload']);
                    clientUid = resp['payload']['uid'];
                    NotifyInfo("Account Registered!");
                    loggedIn = true;
                } else {
                    throw("Error, got a bad response for registration request: " + Json::Write(resp));
                }
            }
            // RejoinIfPriorScope();
            startnew(CoroutineFunc(SendPingLoop));  // send PING every 5s
            startnew(CoroutineFunc(ReadAllMessagesForever));
        }

        bool get_IsLoggedIn() const {
            return loggedIn;
        }

        // rejoin handled on server side now
        // void RejoinIfPriorScope() {
        //     // if we were connected and in a game lobby, room, or game
        //     if (priorScope > 0 && lobbyInfo !is null) {
        //         SendPayload("JOIN_LOBBY", JsonObject1("name", lobbyInfo.name));
        //         if (priorScope > 1 && roomInfo !is null) {
        //             if (roomInfo.join_code.IsSome())
        //                 SendPayload("JOIN_CODE", JsonObject1("code", roomInfo.join_code.GetOr("")));
        //             else
        //                 SendPayload("JOIN_ROOM", JsonObject1("name", roomInfo.name));
        //             if (priorScope > 2 && gameInfoFull !is null) {
        //                 SendPayload("JOIN_GAME_NOW");
        //             }
        //         }
        //     }
        // }

        void ReadAllMessagesForever() {
            string type;
            while (IsConnected) {
                auto msg = ReadMessage();
                if (msg is null || msg.GetType() == Json::Type::Null) continue;
                if (msg.GetType() != Json::Type::Object) {
                    if (IsConnected)
                        NotifyWarning("Got a message that was not an object: " + Json::Write(msg));
                    continue;
                }
                if (msg.HasKey("server")) MsgHandler_Server(msg);
                else if (msg.HasKey("scope")) MsgHandler_Scope(msg);
                else if (!HandleMetaMessages(msg)) {
                    if (!msg.HasKey("type")) warn("msg has no type field: " + Json::Write(msg));
                    else if (msg["type"].GetType() != Json::Type::String) warn("msg type not a string: " + Json::Write(msg));
                    else {
                        type = msg["type"];
                        if (type.StartsWith("G_") && IsInGame) {
                            gameEngine.MessageHandler(msg);
                        } else {
                            auto handlers = GetMessageHandlers(type);
                            if (handlers is null) throw("handlers should never be null!");
                            for (uint i = 0; i < handlers.Length; i++) handlers[i](msg);
                            if (handlers.Length == 0) warn("Unhandled message of type: " + type);
                        }
                    }
                }
            }
        }

        void SendPingLoop() {
            uint sleepTo;
            while (IsConnected) {
                yield();
                sleepTo = Time::Now + 5000;
                SendRaw("PING");
                while (Time::Now < sleepTo) yield();
            }
        }

        Json::Value@ ReadMessage() {
            while (IsConnected && !socket.CanRead() && socket.Available() < 2) yield();
            if (socket.Available() < 2) {
                // todo: something went wrong
                warn("We don't have enough data to read -- connection issues mb?");
                this.Disconnect();
                return null;
            }
            auto msgLen = socket.ReadUint16();
            dev_print("Reading message of length: " + msgLen);
            // ! I think reading a socket can cause TM to hang if the server doesn't finish writing out the msg
            while (IsConnected && socket.Available() < msgLen && socket.CanWrite()) yield();
            if (socket.Available() < msgLen) {
                // todo: something went wrong
                warn("We don't have enough data to read -- connection issues mb?");
                this.Disconnect();
                return null;
            }
            auto rawMsg = socket.ReadRaw(msgLen);
            if (rawMsg == "END") {
                this.Disconnect();
                return null;
            }
            dev_print("Got message: " + rawMsg);
            auto jMsg = Json::Parse(rawMsg);
            if (HandleMetaMessages(jMsg)) {
                // an error occurred
                return null;
            }
            return jMsg;
        }

        bool HandleMetaMessages(Json::Value@ jMsg) {
            if (jMsg.GetType() != Json::Type::Object) return false;
            if (jMsg.HasKey("error")) {
                NotifyError("Server: " + string(jMsg['error']));
            } else if (jMsg.HasKey("warning")) {
                NotifyWarning("Server: " + string(jMsg['warning']));
            } else if (jMsg.HasKey("info")) {
                NotifyInfo("Server: " + string(jMsg['info']));
            } else {
                return false;
            }
            return true;
        }

    	void SendPayload(const string&in type, const Json::Value@ payload, CGF::Visibility visibility) {
            auto toSend = Json::Object();
            toSend['type'] = type;
            toSend['payload'] = payload;
            toSend['visibility'] = tostring(visibility);
            auto sendMsg = Json::Write(toSend);
            this.SendRaw(sendMsg);
    	}

    	void SendPayload(const string&in type, const Json::Value@ payload) {
            SendPayload(type, payload, CGF::Visibility::global);
        }

    	void SendPayload(const string&in type) {
            SendPayload(type, EMPTY_JSON_OBJ, CGF::Visibility::global);
        }

        void SendRaw(const string &in msg) {
            uint16 len = msg.Length;
            bool wrote = socket.Write(len);
            if (wrote) {
                if (len > 5) dev_print("Sending message of length: " + len + ": " + msg);
                wrote = socket.WriteRaw(msg);
            }
            if (!wrote) {
                // socket disconnected
                this.Disconnect();
            }
        }

        void SendLeave() {
            SendPayload("LEAVE", Json::Object(), CGF::Visibility::global);
        }

    	CGF::User@ get_User() override {
            return null;
        }

        void Disconnect(bool forever = false) {
            if (IsDisconnected || IsTimedOut || IsShutdown) return;
            // set disconnected first b/c SendRaw will try to disconnect upon failure
            state = !forever ? ClientState::Disconnected : ClientState::DoNotReconnect;
            SendRaw("END");
            print("Client for " + name + " sent END and disconnected.");
            this.socket.Close();
        }

        /**
         * 88      dP"Yb   dP""b8 88 88b 88    dP    db    88   88 888888 88  88
         * 88     dP   Yb dP   `" 88 88Yb88   dP    dPYb   88   88   88   88  88
         * 88  .o Yb   dP Yb  "88 88 88 Y88  dP    dP__Yb  Y8   8P   88   888888
         * 88ood8  YbodP   YboodP 88 88  Y8 dP    dP""""Yb `YbodP'   88   88  88
         *
         * LOGIN/AUTH
         */

        bool Login(Json::Value@ account) {
            SendPayload("LOGIN", account, CGF::Visibility::none);
            auto resp = ReadMessage();
            if (!IsJsonObject(resp)) return false;
            if ("LOGGED_IN" != resp['type']) {
                return false;
            }
            return true;
        }

        Json::Value@ RegisterAccount() {
            auto pl = Json::Object();
            pl['username'] = name; // name.StartsWith("DebugClient-") ? name : LocalPlayersName;
            pl['wsid'] = LocalPlayersWSID;
            SendPayload("REGISTER", pl, CGF::Visibility::none);
            auto acct = ReadMessage();
            dev_print("Got account: " + Json::Write(acct));
            return acct;
        }


        /**
         * .dP"Y8 888888    db    888888 888888
         * `Ybo."   88     dPYb     88   88__
         * o.`Y8b   88    dP__Yb    88   88""
         * 8bodP'   88   dP""""Yb   88   888888
         *
         * STATE
         */

        // The current game state (room -> game)
        GameState get_CurrGameState() {
            if (IsInGame) return GameState::Started;
            if (IsInRoom) {
                if (gameStartTime < 0) return GameState::NotStarted;
                if (gameStartTime > Time::Now) return GameState::StartingSoon;
                if (gameStartTime <= Time::Now) return GameState::Started;
            }
            if (IsMainLobby || IsInGameLobby) return GameState::None;
            warn("CurrGameState found all conditions were false, returning None as default.");
            return GameState::None;
        }

        bool get_IsGameStartingSoon() { return CurrGameState == GameState::StartingSoon; }
        bool get_IsGameStarted() { return CurrGameState == GameState::Started; }
        bool get_IsGameNotStarted() { return CurrGameState == GameState::NotStarted; }
        bool get_IsGameNone() { return CurrGameState == GameState::None; }

        float get_GameStartingIn() {
            if (IsGameStartingSoon || IsGameStarted) {
                return float(gameStartTime - Time::Now) / 1000.;
            }
            return -1;
        }

        /**
         * 88  88    db    88b 88 8888b.  88     888888     8b    d8 .dP"Y8  dP""b8 .dP"Y8
         * 88  88   dPYb   88Yb88  8I  Yb 88     88__       88b  d88 `Ybo." dP   `" `Ybo."
         * 888888  dP__Yb  88 Y88  8I  dY 88  .o 88""       88YbdP88 o.`Y8b Yb  "88 o.`Y8b
         * 88  88 dP""""Yb 88  Y8 8888Y"  88ood8 888888     88 YY 88 8bodP'  YboodP 8bodP'
         *
         * HANDLE MSGs
         */

        CGF::MessageHandler@[] emptyMsgHandlers;
        CGF::MessageHandler@[]@ GetMessageHandlers(const string &in type) {
            if (messageHandlers.Exists(type)) {
                return cast<CGF::MessageHandler@[]>(messageHandlers[type]);
            } else {
                return emptyMsgHandlers;
            }
        }

        /* Message Handlers */

        // special handler for server msgs
        void MsgHandler_Server(Json::Value@ j) {
            @latestServerInfo = j["server"];
        }

        void MsgHandler_Scope(Json::Value@ j) {
            // format: "<int>|<string>"
            priorScope = currScope;
            this.currScope = Scope(string(j["scope"])[0] - 0x30);
            this.scopeName = string(j["scope"]).SubStr(2);
            // on scope change
            OnChangedScope();
        }

        void OnChangedScope() {
            currentPlayers.DeleteAll();
            readyStatus.DeleteAll();
            currAdmins.Resize(0);
            currMods.Resize(0);
            @mapsList = Json::Array();
            // currTeams.Resize(0);
            uidToTeamNb.DeleteAll();
            gameStartTS = -1.;
            gameStartTime = -1.;
            // reset chat by strategically setting values to null -- very cheap
            @mainChat[chatNextIx == 0 ? (mainChat.Length - 1) : (chatNextIx - 1)] = null;
            @mainChat[chatNextIx] = null;
            @mainChat[(chatNextIx + 1) % mainChat.Length] = null;
            //
            if (IsInGame) {
                @gameInfoFull = null;
                startnew(CoroutineFunc(gameEngine.OnGameStart));
            }
            if (priorScope == 3 && IsInRoom) {
                _GameReplayNbMsgs = 0;
                startnew(CoroutineFunc(gameEngine.OnGameEnd));
            }
            if (IsInRoom) {
                cachedThumbnails.DeleteAll();
            }
        }

        bool MsgHandler_LobbyInfo(Json::Value@ j) {
            if (lobbyInfo is null) @lobbyInfo = LobbyInfo(j['payload']);
            else lobbyInfo.UpdateFrom(j['payload']);
            return true;
        }

        bool MsgHandler_RoomInfo(Json::Value@ j) {
            @roomInfo = RoomInfo(j['payload']);
            if (roomInfo.n_teams != currTeams.Length) {
                currTeams.Resize(roomInfo.n_teams);
                for (uint i = 0; i < currTeams.Length; i++) {
                    currTeams[i].Resize(0);
                }
            }
            return true;
        }

        bool MsgHandler_NewRoom(Json::Value@ j) {
            if (lobbyInfo is null) {
                warn("New Room but lobby info is null! Skipping");
            } else {
                lobbyInfo.AddRoom(j['payload']);
            }
            return true;
        }

        bool MsgHandler_RoomUpdate(Json::Value@ j) {
            auto pl = j['payload'];
            string name = pl['name'];
            int n_players = pl['n_players'];
            for (uint i = 0; i < lobbyInfo.rooms.Length; i++) {
                auto room = lobbyInfo.rooms[i];
                if (room.name != name) continue;
                room.n_players = n_players;
                break;
            }
            return true;
        }

        // todo: finish this
        bool MsgHandler_PlayerEvent(Json::Value@ j) {
            string type = j['type'];
            Json::Value@ pl = j['payload'];
            if (type == "PLAYER_LEFT") RemovePlayer(pl['uid']);
            else if (type == "PLAYER_JOINED") AddPlayer(pl['uid'], pl['username']);
            else if (type == "PLAYER_LIST") UpdatePlayersFromCanonical(pl['players']);
            else {
                throw("Msg of incorrect type sent to PlayerEvent handler: " + type);
                return false;
            }
            return true;
        }

        void RemovePlayer(const string &in uid) {
            currentPlayers.Delete(uid);
            readyStatus.Delete(uid);
            RemovePlayerFromTeams(uid);
            RecalcReadyCount();
        }

        void AddPlayer(const string &in uid, const string &in username) {
            currentPlayers[uid] = username;
            readyStatus[uid] = false;
        }

        void UpdatePlayersFromCanonical(const Json::Value@ players) {
            if (players is null || players.GetType() != Json::Type::Array) {
                warn("UpdatePlayersFromCanonical given a json value that wasn't an array");
                return;
            }
            currentPlayers.DeleteAll();
            for (uint i = 0; i < players.Length; i++) {
                auto item = players[i];
                string uid = item['uid'];
                currentPlayers[uid] = string(item['username']);
                if (!readyStatus.Exists(uid)) readyStatus[uid] = false;
            }
        }

        bool MsgHandler_AdminModStatus(Json::Value@ j) {
            auto admins = j['payload']['admins'];
            auto mods = j['payload']['mods'];
            currAdmins.Resize(admins.Length);
            currMods.Resize(mods.Length);
            for (uint i = 0; i < admins.Length; i++) {
                currAdmins[i] = admins[i];
            }
            for (uint i = 0; i < mods.Length; i++) {
                currMods[i] = mods[i];
            }
            return true;
        }

        void RemovePlayerFromTeams(const string &in uid) {
            uidToTeamNb.Delete(uid);
            for (uint i = 0; i < currTeams.Length; i++) {
                auto @team = currTeams[i];
                int ix = team.Find(uid);
                while (ix >= 0) {
                    team.RemoveAt(uint(ix));
                    ix = team.Find(uid);
                }
            }
        }

        void AddPlayerToTeam(const string &in uid, int team) {
            if (team < 0 or team >= roomInfo.n_teams) {
                warn("Tried to add player to invalid team");
                return;
            }
            uidToTeamNb[uid] = team;
            currTeams[team].InsertLast(uid);
        }

        int PlayerIsOnTeam(const string &in uid) {
            for (uint i = 0; i < currTeams.Length; i++) {
                if (currTeams[i].Find(uid) >= 0) {
                    return i;
                }
            }
            // return -1;
            // for some reason this does not seem to work correctly.
            if (!uidToTeamNb.Exists(uid)) return -1;
            int team;
            if (uidToTeamNb.Get(uid, team)) {
                return team;
            }
            return -1;
            // return int(uidToTeamNb[uid]);
        }

        bool MsgHandler_TeamsEvent(Json::Value@ j) {
            string type = j['type'];
            if (type == "PLAYER_JOINED_TEAM") {
                string uid = j['payload']['uid'];
                int team = j['payload']['team'];
                RemovePlayerFromTeams(uid);
                AddPlayerToTeam(uid, team);
            } else if (type == "LIST_TEAMS") {
                auto teams = j['payload']['teams'];
                if (IsJsonArray(teams) && IsJsonArray(teams[0])) {
                    uidToTeamNb.DeleteAll();
                    currTeams.Resize(teams.Length);
                    for (uint i = 0; i < teams.Length; i++) {
                        auto players = teams[i];
                        currTeams[i].Resize(players.Length);
                        for (uint pn = 0; pn < players.Length; pn++) {
                            currTeams[i][pn] = players[pn];
                        }
                    }
                } else warn("LIST_TEAMS incorrect payload format: " + Json::Write(j));
            }
            return true;
        }

        bool MsgHandler_ReadyEvent(Json::Value@ j) {
            string type = j['type'];
            if (type == "LIST_READY_STATUS") {
                auto uids = j['payload']['uids'];
                auto ready = j['payload']['ready'];
                if (IsJsonArray(uids) && IsJsonArray(ready)) {
                    for (uint i = 0; i < uids.Length; i++) {
                        readyStatus[uids[i]] = bool(ready[i]);
                    }
                }
            }
            else if (type == "PLAYER_READY") {
                bool is_ready = j['payload']['is_ready'];
                string uid = j['payload']['uid'];
                readyStatus[uid] = is_ready;
            }
            RecalcReadyCount();
            return true;
        }

        void RecalcReadyCount() {
            readyCount = 0;
            auto @keys = readyStatus.GetKeys();
            for (uint i = 0; i < keys.Length; i++) {
                if (bool(readyStatus[keys[i]])) readyCount += 1;
            }
        }

        bool MsgHandler_GameReplayHandler(Json::Value@ j) {
            string type = j['type'];
            if (type == "GAME_REPLAY_START") {
                this._GameReplayInProgress = true;
                this._GameReplayNbMsgs = int(j['payload']['n_msgs']);
            } else if (type == "GAME_REPLAY_END") {
                this._GameReplayInProgress = false;
                // this.gameEngine.OnReplayEnd();
            } else return false;
            return true;
        }

        bool get_GameReplayInProgress() {
            return _GameReplayInProgress;
        }

        int get_GameReplayNbMsgs() {
            // if (GameReplayInProgress) return 0;
            return _GameReplayNbMsgs;
        }

        bool MsgHandler_GameStartHandler(Json::Value@ j) {
            string type = j['type'];
            if (type == "GAME_START_ABORT") {
                gameStartTS = -1.;
                gameStartTime = -1.;
            }
            else if (type == "GAME_STARTING_AT") {
                auto pl = j['payload'];
                gameStartTS = pl['start_time'];
                gameStartTime = Time::Now + float(pl['wait_time'] * 1000.);
                startnew(CoroutineFunc(JoinGameWhenReady));
            }
            else throw("Uknown event");
            return true;
        }

        void JoinGameWhenReady() {
            while (IsGameStartingSoon)
                yield();
            if (!IsGameStarted) return;
            SendPayload("JOIN_GAME_NOW");
        }

        bool MsgHandler_GameInfo(Json::Value@ j) {
            // {n_msgs: int}
            // @gameInfoFull = GameInfoFull(j["payload"]);
            return true;
        }

        bool MsgHandler_GameInfoFull(Json::Value@ j) {
            @gameInfoFull = GameInfoFull(j["payload"]);
            // for (uint i = 0; i < gameInfoFull.players.Length; i++) {
            //     auto user = gameInfoFull.players[i];
            //     AddPlayer(user.uid, user.username);
            // }
            return true;
        }

        bool MsgHandler_MapsInfoFull(Json::Value@ j) {
            @mapsList = j["payload"]['maps'];
            startnew(CoroutineFunc(CacheMapThumbnails));
            return true;
        }

        bool get_IsMainLobby() { return currScope == Scope::MainLobby; }
        bool get_IsInGameLobby() { return currScope == Scope::InGameLobby; }
        bool get_IsInRoom() { return currScope == Scope::InRoom; }
        bool get_IsInGame() { return currScope == Scope::InGame; }

        array<Json::Value@>@ get_mainChat() {
            if (IsMainLobby) return this.globalChat;
            if (IsInGameLobby) return this.lobbyChat;
            if (IsInRoom) return this.roomChat;
            if (IsInGame) return this.roomChat;
            return null;
        }

        uint chatNextIx {
            get {
                if (IsMainLobby) return this.globalChatNextIx;
                if (IsInGameLobby) return this.lobbyChatNextIx;
                if (IsInRoom) return this.roomChatNextIx;
                if (IsInGame) return this.roomChatNextIx;
                return 9999;  // should never be true
            }
            set {
                if (IsMainLobby) this.globalChatNextIx = value;
                if (IsInGameLobby) this.lobbyChatNextIx = value;
                if (IsInRoom) this.roomChatNextIx = value;
                if (IsInGame) this.roomChatNextIx = value;
            }
        }

        array<Json::Value@>@ get_currSecondaryChatArray() {
            // if (IsMainLobby) return null;
            // if (IsInGameLobby) return null;
            // if (IsInRoom) return null;
            if (IsInGame) return this.mapChat;
            return null;
        }

        uint secChatNextIx {
            get {
                if (IsInGame) return this.mapChatNextIx;
                return 9999;  // should never be true
            }
            set {
                if (IsInGame) this.roomChatNextIx = value;
            }
        }

        void InsertToMainChat(Json::Value@ j) {
            @mainChat[chatNextIx] = j;
            chatNextIx = (chatNextIx + 1) % mainChat.Length;
            @mainChat[chatNextIx] = null;
        }

        bool MsgHandler_Chat(Json::Value@ j) {
            print("Handling chat msg: ["+int(float(j['ts']))+"]" + Json::Write(j));
            InsertToMainChat(j);
            return true;
            // if ((IsMainLobby || IsInGameLobby) && j['visibility'] == "global") {
            // }
            // return false;
        }

        /* Exposed Methods */

        const string GetPlayerName(const string &in uid) {
            string name;
            if (currentPlayers.Get(uid, name)) return name;
            return "??? " + uid.SubStr(0, 6);
        }

        void MarkReady(bool isReady) {
            readyStatus[clientUid] = isReady;
            SendPayload("MARK_READY", JsonObject1("ready", Json::Value(isReady)));
        }

        bool GetReadyStatus(const string &in uid) {
            bool rs;
            if (readyStatus.Get(uid, rs)) return rs;
            return false;
        }

        void SendChat(const string &in msg, CGF::Visibility visibility = CGF::Visibility::global) {
            auto pl = Json::Object();
            pl['content'] = msg;
            SendPayload("SEND_CHAT", pl, visibility);
        }

        void JoinLobby(const string &in name) {
            // if (currScope != Scope::MainLobby) return;
            auto pl = Json::Object();
            pl['name'] = name;
            SendPayload("JOIN_LOBBY", pl, CGF::Visibility::global);
        }

        void LeaveLobby() {
            // if (currScope != Scope::InGameLobby) return;
            // SendPayload("LEAVE", Json::Object(), CGF::Visibility::global);
            SendLeave();
        }

        void JoinRoom(const string &in name) {
            auto pl = Json::Object();
            pl['name'] = name;
            SendPayload("JOIN_ROOM", pl, CGF::Visibility::global);
        }

        void JoinRoomViaCode(const string &in joinCode) {
            auto pl = Json::Object();
            pl['code'] = joinCode;
            SendPayload("JOIN_CODE", pl, CGF::Visibility::global);
        }

        void AddMessageHandler(const string &in type, CGF::MessageHandler@ handler) {
            if (!messageHandlers.Exists(type)) {
                @messageHandlers[type] = array<CGF::MessageHandler@>();
            }
            array<CGF::MessageHandler@>@ handlers;
            if (messageHandlers.Get(type, @handlers)) {
                handlers.InsertLast(handler);
            } else {
                throw("Had missing handlers array -- should never happen.");
            }
        }

        /* MAP STUFF */

        /*

        class Map(Document):
            TrackID: Indexed(int, unique=True)
            UserID: Indexed(int)
            Username: Indexed(str)
            AuthorLogin: Indexed(str)
            Name: Indexed(str)
            GbxMapName: Indexed(str)
            TrackUID: str
            TitlePack: Indexed(str)
            ExeVersion: Indexed(str)
            ExeBuild: Indexed(str)
            Mood: str
            ModName: str | None
            AuthorTime: int
            ParserVersion: int
            UploadedAt: str
            UpdatedAt: str
            UploadTimestamp: float
            UpdateTimestamp: float
            Tags: str | None
            TypeName: str
            StyleName: Indexed(str) | None
            RouteName: str
            LengthName: str
            LengthSecs: Indexed(int)
            LengthEnum: int
            DifficultyName: str
            Laps: int
            Comments: str
            Downloadable: bool
            Unlisted: bool
            Unreleased: bool
            RatingVoteCount: int
            RatingVoteAverage: float
            VehicleName: str
            EnvironmentName: str
            HasScreenshot: bool
            HasThumbnail: bool
         */


        void CacheMapThumbnails() {
            for (uint i = 0; i < mapsList.Length; i++) {
                startnew(CoroutineFuncUserdata(CacheThumbnail), mapsList[i]);
            }
        }

        dictionary cachedThumbnails;

        void CacheThumbnail(ref@ _map) {
            Json::Value@ map = cast<Json::Value>(_map);
            string url = MapThumbUrl(map);
            logcall("CacheThumbnail", "URL: " + url);
            string trackId = tostring(int(map['TrackID']));
            if (url.Length == 0) {
                @cachedThumbnails[trackId] = null;
            }
            if (cachedThumbnails.Exists(trackId)) return;
            @cachedThumbnails[trackId] = DownloadThumbnail(url);
        }

        /**
         * returns true only after we failed to download a thumbnail
         * returns false when a thumbnail exists or when it's being downloaded
         */
        bool MapDoesNotHaveThumbnail(const string &in trackId) const {
            if (cachedThumbnails.Exists(trackId)) {
                return GetCachedMapThumb(trackId) is null;
            }
            return false;
        }

        const CGF_Texture@ GetCachedMapThumb(const string &in trackId) const {
            if (!cachedThumbnails.Exists(trackId)) return null;
            return cast<CGF_Texture>(cachedThumbnails[trackId]);
        }

        CGF_Texture@ DownloadThumbnail(const string &in url) {
            logcall("DownloadThumbnail", "Starting Download: " + url);
            auto r = Net::HttpGet(url);
            r.Headers['User-Agent'] = "TM_Plugin:CommunityGameFramework/contact:@XertroV";
            r.Start();
            while (!r.Finished()) yield();
            if (r.ResponseCode() >= 300) {
                warn("DownloadThumbnail failed with error code " + r.ResponseCode());
            } else {
                logcall("DownloadThumbnail", "Downloaded: " + url);
                auto buf = r.Buffer();
                return CGF_Texture(buf);
            }
            return null;
        }


        /* DEBUG STUFF */

        void DrawDebug() {
            if (UI::CollapsingHeader(name)) {
                UI::Text("State: " + tostring(state));
                UI::Text("Remote IP: " + tostring(socket.GetRemoteIP()));
                UI::Text("Server Info: " + (latestServerInfo is null ? "null" : Json::Write(latestServerInfo)));
            }
        }
    }
}
