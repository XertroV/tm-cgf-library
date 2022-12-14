namespace Game {
    interface Engine {
        // // Reset the game state, e.g., on new game load
        // void ResetState();

        // called when the game is starting
        void OnGameStart();

        // called when the game ends
        void OnGameEnd();

        // // called when a replay of game events finishes
        // void OnReplayEnd();

        // handle game messages
        bool MessageHandler(Json::Value@ msg);


    }
}
