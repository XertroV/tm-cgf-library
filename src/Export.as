namespace CGF {
    Client@ mainClient = null;

    Client@ GetMainClient() {
        if (mainClient is null) {
            try {
                @mainClient = Game::Client();
            } catch {
                if (getExceptionInfo() == "LoginFailed") {
                    NotifyInfo("Registering new account...");
                    @mainClient = Game::Client();
                } else {
                    warn("Got unexpected error starting client: " + getExceptionInfo());
                    throw(getExceptionInfo());
                }
            }
        }
        return mainClient;
    }
}
