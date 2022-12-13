// returns the name of the local player, or an empty string if this is not yet known
const string get_LocalPlayersName() {
    try {
        return cast<CTrackMania>(GetApp()).MenuManager.ManialinkScriptHandlerMenus.LocalUser.Name;
    } catch {}
    return "";
}

// returns the WebServicesUserId of the local player, or an empty string if this is not yet known
const string get_LocalPlayersWSID() {
    try {
        return cast<CTrackMania>(GetApp()).MenuManager.ManialinkScriptHandlerMenus.LocalUser.WebServicesUserId;
    } catch {}
    return "";
}

bool CurrentlyInMap {
    get {
        return GetApp().RootMap !is null && GetApp().CurrentPlayground !is null;
    }
}
