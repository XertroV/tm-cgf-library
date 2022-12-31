namespace CGF {
    Client@ mainClient = null;

    Client@ GetMainClient() {
        if (mainClient is null) {
            @mainClient = Game::Client("");
        }
        return mainClient;
    }
}
