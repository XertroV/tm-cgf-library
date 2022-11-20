namespace Game {
    const string StorageFileTemplate = IO::FromStorageFolder("account_|CLIENTNAME|.json");

    enum Scope {
        MainLobby, InGameLobby, InRoom, InGame
    }

    class Client : CGF::Client {
        Net::Socket@ socket = Net::Socket();
        string name;
        string fileName;
        bool accountExists;
        bool shutdown = false;

        Json::Value@ latestServerInfo;

        Scope currScope = Scope::MainLobby;

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
            name = _name.Length == 0 ? LocalPlayersName : _name;
            fileName = StorageFileTemplate.Replace("|CLIENTNAME|", name);
            accountExists = IO::FileExists(fileName);
            try {
                socket.Connect(S_Host, S_Port);
            } catch {
                warn("Failed to connect to CGF server: " + getExceptionInfo());
            }
            OnConnected();
            SendChat("Hi I'm " + name);
        }

        ~Client() {
            Disconnect();
        }

        void OnConnected() {
            // expect server version
            auto msg = ReadMessage();
            @latestServerInfo = msg["server"];
            string ver = string(latestServerInfo["version"]);
            int nbClients = int(latestServerInfo["nbClients"]);
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
                if ("REGISTERED" == resp['type']) {
                    accountExists = true;
                    Json::ToFile(fileName, resp['payload']);
                    NotifyInfo("Account Registered!");
                } else {
                    warn("Error, got a bad response for registration request: " + Json::Write(resp));
                }
            }
            startnew(CoroutineFunc(SendPingLoop));  // send PING every 5s
            startnew(CoroutineFunc(ReadAllMessagesForever));
        }

        void ReadAllMessagesForever() {
            string type;
            while (true) {
                auto msg = ReadMessage();
                if (msg.HasKey("server")) MsgHandler_Server(msg);
                else if (msg.HasKey("scope")) MsgHandler_Scope(msg);
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
            while (!this.shutdown) {
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
            pl['username'] = LocalPlayersName;
            pl['wsid'] = LocalPlayersWSID;
            SendPayload("REGISTER", pl, CGF::Visibility::none);
            auto acct = ReadMessage();
            dev_print("Got account: " + Json::Write(acct));
            return acct;
        }

        Json::Value@ ReadMessage() {
            while (!shutdown && socket.Available() < 2) yield();
            auto msgLen = socket.ReadUint16();
            dev_print("Reading message of length: " + msgLen);
            auto rawMsg = socket.ReadRaw(msgLen);
            // ignore PINGs
            if (rawMsg == "PING") return ReadMessage();
            dev_print("Got message: " + rawMsg);
            auto jMsg = Json::Parse(rawMsg);
            if (HandleMetaMessages(jMsg)) {
                // an error occurred
                return Json::Value();
            }
            return jMsg;
        }

        bool HandleMetaMessages(Json::Value@ jMsg) {
            if (jMsg.HasKey("error")) {
                // oh no
                NotifyError("Server: " + string(jMsg['error']));
            } else if (jMsg.HasKey("warning")) {
                NotifyWarning("Server: " + string(jMsg['warning']));
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

        void SendRaw(const string &in msg) {
            uint16 len = msg.Length;
            socket.Write(len);
            if (len > 5) dev_print("Sending message of length: " + len);
            socket.WriteRaw(msg);
        }

    	CGF::User@ get_User() override {
            return null;
        }

        void Disconnect() {
            if (this.shutdown) return;
            SendRaw("END");
            this.shutdown = true;
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
            dev_print("set scope: " + string(j["scope"]));
            dev_print("curr scope: " + tostring(this.currScope));
        }

        bool MsgHandler_Chat(Json::Value@ j) {
            print("Handling chat msg: " + Json::Write(j));
            if (currScope == Scope::MainLobby && j['visibility'] == "global") {
                @globalChat[globalChatNextIx] = j;
                globalChatNextIx = (globalChatNextIx + 1) % globalChat.Length;
            } else {
                return false;
            }
            return true;
        }

        /* Exposed Methods */

        void SendChat(const string &in msg, CGF::Visibility visibility = CGF::Visibility::global) {
            auto pl = Json::Object();
            pl['content'] = msg;
            SendPayload("SEND_CHAT", pl, visibility);
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
                UI::Text("Connected: " + tostring(socket.CanRead()));
                UI::Text("Shutdown: " + tostring(this.shutdown));
                UI::Text("Remote IP: " + tostring(socket.GetRemoteIP()));
                UI::Text("Server Info: " + (latestServerInfo is null ? "null" : Json::Write(latestServerInfo)));
            }
        }
    }
}
