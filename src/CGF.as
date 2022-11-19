namespace Game {
    class Client : CGF::Client {
        Net::Socket@ socket = Net::Socket();
        string name;
        string fileName;
        bool accountExists;
        bool shutdown = false;

        Client(const string &in _name = "") {
            name = _name.Length == 0 ? LocalPlayersName : _name;
            fileName = IO::FromStorageFolder("account_" + name + ".json");
            accountExists = IO::FileExists(fileName);
            try {
                socket.Connect(S_Host, S_Port);
            } catch {
                warn("Failed to connect to CGF server: " + getExceptionInfo());
            }
            OnConnected();
        }

        ~Client() {
            Disconnect();
        }

        void OnConnected() {
            // expect server version
            auto msg = ReadMessage();
            print("Connected. Server version: " + string(msg["Server Version"]));
            // login if possible
            if (accountExists) {
                auto deets = Json::FromFile(fileName);
                if (!Login(deets)) {
                    NotifyError("Failed to log in :(");
                    IO::Move(fileName, fileName + "_bak_" + Time::Stamp);
                    throw('LoginFailed');
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
            startnew(CoroutineFunc(PingLoop));
        }

        void PingLoop() {
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
            if (jMsg.HasKey("error")) {
                // oh no
                NotifyError(jMsg['error']);
                warn("Error from server: " + string(jMsg['error']));
                return Json::Value();
            }
            return jMsg;
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
            this.shutdown = true;
            SendRaw("END");
            this.socket.Close();
        }


        void SendChat(const string &in msg) {
            auto pl = Json::Object();
            pl['content'] = msg;
            SendPayload("SEND_CHAT", pl, CGF::Visibility::global);
        }
    }
}
