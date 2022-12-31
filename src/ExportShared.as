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
        void SendPayload(const string &in type, const Json::Value@ payload, Visibility visibility);
        void SendChat(const string &in msg, CGF::Visibility visibility = CGF::Visibility::global);
        void AddMessageHandler(const string &in type, MessageHandler@ handler);
    }

    // shared
    interface User {
        const string get_Name();
        const string get_Id();
    }

    interface GameEngine {
        // void ProcessGameMessage(const string &in )
    }

    enum MaxDifficulty {
        Beginner = 0,
        Intermediate = 1,
        Advanced = 2,
        Expert = 3,
        Lunatic = 4,
        Impossible = 5
    }

    enum MapSelection {
        RandomWithFilter = 1, MapPack = 2, TrackOfTheDay = 3, RoyalTraining = 4
    }

    const string MapSelectionStr(MapSelection ms) {
        if (ms == MapSelection::RandomWithFilter) {
            return "Random (filtered)";
        } else if (ms == MapSelection::MapPack) {
            return "Map Pack";
        } else if (ms == MapSelection::TrackOfTheDay) {
            return "Track of the Day";
        } else if (ms == MapSelection::RoyalTraining) {
            return "Royal Training Map Pack";
        }
        return "Unknown";
    }
}
