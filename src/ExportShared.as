namespace CGF {
    // shared
    enum Visibility {
        none, global, team, map
    }

    // shared
    funcdef bool MessageHandler(Json::Value@ msg);

    //shared
    interface Client {
        User@ get_User();
        void SendPayload(const string &in type, Json::Value@ payload, Visibility visibility);
        void SendChat(const string &in msg, CGF::Visibility visibility = CGF::Visibility::global);
        void AddMessageHandler(const string &in type, MessageHandler@ handler);
    }

    // shared
    interface User {
        const string get_Name();
        const string get_Id();
    }
}
