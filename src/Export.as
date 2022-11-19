namespace CGF {
    Client@ mainClient = null;

    Client@ GetCgfClient() {
        if (mainClient is null) {
            @mainClient = Game::Client();
        }
        return mainClient;
    }
}
