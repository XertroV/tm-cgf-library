namespace Game {
    interface Engine {
        // // Reset the game state, e.g., on new game load
        // void ResetState();

        // called when the game is starting
        void OnGameStart();

        // called when the game ends
        void OnGameEnd();

        // handle game messages
        bool MessageHandler(Json::Value@ msg);


    }
}
