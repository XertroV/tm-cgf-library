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

bool get_CurrentlyInMap() {
    return GetApp().CurrentPlayground !is null;
}
