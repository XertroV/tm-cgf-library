namespace CGF {
    // shared
    enum Visibility {
        none, global, team, map
    }

    //shared
    interface Client {
        User@ get_User();
        void SendPayload(const string &in type, Json::Value@ payload, Visibility visibility);
    }

    // shared
    interface User {
        const string get_Name();
        const string get_Id();
    }
}
