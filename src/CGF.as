namespace Game {
    const string StorageFileTemplate = IO::FromStorageFolder("account_|CLIENTNAME|.json");

    enum Scope {
        MainLobby, InGameLobby, InRoom, InGame
    }

    enum ClientState {
        Uninitialized, Connecting, Connected, Disconnected, DoNotReconnect, TimedOut
    }

    class Client : CGF::Client {
        Net::Socket@ socket = Net::Socket();
        string name;
        string fileName;
        bool accountExists;
        ClientState state = ClientState::Uninitialized;
        int connectedAt;

        dictionary currentPlayers;

        Json::Value@ latestServerInfo;
        // Json::Value@ lobbyInfo;
        LobbyInfo@ lobbyInfo;
        RoomInfo@ roomInfo;

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

        // alternative user name is the optional param -- for testing
        Client(const string &in _name = "") {
            AddMessageHandler("SEND_CHAT", CGF::MessageHandler(MsgHandler_Chat));
            AddMessageHandler("ENTERED_LOBBY", CGF::MessageHandler(MsgHandler_LobbyInfo));
            AddMessageHandler("LOBBY_INFO", CGF::MessageHandler(MsgHandler_LobbyInfo));
            AddMessageHandler("ROOM_INFO", CGF::MessageHandler(MsgHandler_RoomInfo));
            AddMessageHandler("PLAYER_LEFT", CGF::MessageHandler(MsgHandler_PlayerEvent));
            AddMessageHandler("PLAYER_JOINED", CGF::MessageHandler(MsgHandler_PlayerEvent));
            AddMessageHandler("PLAYER_LIST", CGF::MessageHandler(MsgHandler_PlayerEvent));
            // AddMessageHandler("PLAYER_JOINED_TEAM", CGF::MessageHandler(MsgHandler_PlayerJoinedTeam));
            // AddMessageHandler("PLAYER_READY", CGF::MessageHandler(MsgHandler_PlayerJoinedTeam));
            // AddMessageHandler("ROOM_STATUS_INFO", CGF::MessageHandler(MsgHandler_PlayerJoinedTeam));

            name = _name.Length == 0 ? LocalPlayersName : _name;
            fileName = StorageFileTemplate.Replace("|CLIENTNAME|", name);
            accountExists = IO::FileExists(fileName);
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

        void ReconnectIfPossible() {
            while (state != ClientState::DoNotReconnect) {
                yield();
                if (!socket.CanWrite() && !socket.CanRead() && socket.Available() == 0) state = ClientState::Disconnected;
                if (IsDisconnected || IsTimedOut) {
                    warn("[ReconnectIfPossible] in 0.5s");
                    sleep(500);  // sleep .5s to avoid trying again too soon
                    Reconnect();
                }
            }
        }

        void Connect(uint timeout = 5000) {
            state = ClientState::Connecting;
            // we must initialize a new socket here b/c otherwise we'll hang on reuse (i.e., via reconnect); fix is to restart the server (wtf?)
            @socket = Net::Socket();
            uint startTime = Time::Now;
            uint timeoutAt = startTime + timeout;
            try {
                socket.Connect(S_Host, S_Port);
            } catch {
                warn("Failed to init connection to CGF server: " + getExceptionInfo());
            }
            while (Time::Now < timeoutAt && !socket.CanWrite() && !socket.CanRead()) {
                yield();
            }
            if (Time::Now >= timeoutAt) {
                warn("Timeout connecting to " + S_Host + ":" + S_Port);
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
        bool get_IsDisconnected() { return state == ClientState::Disconnected; }
        bool get_IsTimedOut() { return state == ClientState::TimedOut; }

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
                if (!Login(deets)) {
                    NotifyError("Failed to log in :(");
                    IO::Move(fileName, fileName + "_bak_" + Time::Stamp);
                    warn('LoginFailed');
                    accountExists = false;
                } else {
                    NotifyInfo("Logged in!");
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
                    NotifyInfo("Account Registered!");
                } else {
                    warn("Error, got a bad response for registration request: " + Json::Write(resp));
                }
            }
            RejoinIfPriorScope();
            startnew(CoroutineFunc(SendPingLoop));  // send PING every 5s
            startnew(CoroutineFunc(ReadAllMessagesForever));
        }

        void RejoinIfPriorScope() {
            // if we were connected and in a game lobby, room, or game
            if (priorScope > 0 && lobbyInfo !is null) {
                SendPayload("JOIN_LOBBY", JsonObject1("name", lobbyInfo.name));
                if (priorScope > 1 && roomInfo !is null) {
                    if (roomInfo.join_code.IsSome())
                        SendPayload("JOIN_CODE", JsonObject1("code", roomInfo.join_code.GetOr("")));
                    else
                        SendPayload("JOIN_ROOM", JsonObject1("name", roomInfo.name));
                }
            }
        }

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
                        auto handlers = GetMessageHandlers(type);
                        if (handlers is null) throw("handlers should never be null!");
                        for (uint i = 0; i < handlers.Length; i++) handlers[i](msg);
                        if (handlers.Length == 0) warn("Unhandled message of type: " + type);
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

        bool Login(Json::Value@ account) {
            SendPayload("LOGIN", account, CGF::Visibility::none);
            auto resp = ReadMessage();
            if (resp.GetType() != Json::Type::Object) return false;
            if ("LOGGED_IN" != resp['type']) {
                return false;
            }
            return true;
        }

        Json::Value@ RegisterAccount() {
            auto pl = Json::Object();
            pl['username'] = name.StartsWith("DebugClient-") ? name : LocalPlayersName;
            pl['wsid'] = LocalPlayersWSID;
            SendPayload("REGISTER", pl, CGF::Visibility::none);
            auto acct = ReadMessage();
            dev_print("Got account: " + Json::Write(acct));
            return acct;
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

    	void SendPayload(const string&in type, Json::Value@ payload, CGF::Visibility visibility) {
            auto toSend = Json::Object();
            toSend['type'] = type;
            toSend['payload'] = payload;
            toSend['visibility'] = tostring(visibility);
            auto sendMsg = Json::Write(toSend);
            this.SendRaw(sendMsg);
    	}

    	void SendPayload(const string&in type, Json::Value@ payload) {
            SendPayload(type, payload, CGF::Visibility::global);
        }


        void SendRaw(const string &in msg) {
            uint16 len = msg.Length;
            socket.Write(len);
            if (len > 5) dev_print("Sending message of length: " + len + ": " + msg);
            socket.WriteRaw(msg);
        }

        void SendLeave() {
            SendPayload("LEAVE", Json::Object(), CGF::Visibility::global);
        }

    	CGF::User@ get_User() override {
            return null;
        }

        void Disconnect() {
            if (IsDisconnected || IsTimedOut) return;
            SendRaw("END");
            state = ClientState::Disconnected;
            print("Client for " + name + " sent END and disconnected.");
            this.socket.Close();
        }

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
            this.currScope = Scope(string(j["scope"])[0] - 0x30);
            this.scopeName = string(j["scope"]).SubStr(2);
            // on scope change
            OnChangedScope();
        }

        void OnChangedScope() {
            this.currentPlayers.DeleteAll();
            // reset chat by strategically setting values to null -- very cheap
            @mainChat[chatNextIx == 0 ? (mainChat.Length - 1) : (chatNextIx - 1)] = null;
            @mainChat[chatNextIx] = null;
            @mainChat[(chatNextIx + 1) % mainChat.Length] = null;
        }

        bool MsgHandler_LobbyInfo(Json::Value@ j) {
            if (lobbyInfo is null) @lobbyInfo = LobbyInfo(j['payload']);
            else lobbyInfo.UpdateFrom(j['payload']);
            return true;
        }

        bool MsgHandler_RoomInfo(Json::Value@ j) {
            @roomInfo = RoomInfo(j['payload']);
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
            currentPlayers.Delete(uid);
        }

        void AddPlayer(const string &in uid, const string &in username) {
            currentPlayers[uid] = username;
        }

        void UpdatePlayersFromCanonical(const Json::Value@ players) {
            if (players is null || players.GetType() != Json::Type::Array) {
                warn("UpdatePlayersFromCanonical given a json value that wasn't an array");
                return;
            }
            currentPlayers.DeleteAll();
            for (uint i = 0; i < players.Length; i++) {
                auto item = players[i];
                currentPlayers[item['uid']] = string(item['username']);
            }
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
            if (IsMainLobby) return null;
            if (IsInGameLobby) return null;
            if (IsInRoom) return null;
            if (IsInGame) return this.mapChat;
            return null;
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
