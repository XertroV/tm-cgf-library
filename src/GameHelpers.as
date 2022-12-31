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


void SetLoadingScreenText(const string &in text, const string &in secondaryText = "Initializing...") {
    auto fm = GetApp().LoadProgress.FrameManialink;
    if (fm is null) return;
    if (fm.Childs.Length == 0) return;
    auto c1 = cast<CControlFrame>(fm.Childs[0]);
    if (c1 is null || c1.Childs.Length == 0) return;
    auto c2 = cast<CControlFrame>(c1.Childs[0]);
    if (c2 is null || c2.Childs.Length < 3) return;
    auto label = cast<CControlLabel>(c2.Childs[2]);
    auto secLabel = cast<CControlLabel>(c2.Childs[1]);
    if (label is null) return;
    label.Label = text;
    if (secLabel is null) return;
    secLabel.Label = secondaryText;
}

int GetMostRecentGhostTime() {
    auto dfm = GetApp().Network.ClientManiaAppPlayground.DataFileMgr;
    auto nbGhosts = dfm.Ghosts.Length;
    auto mostRecent = dfm.Ghosts[nbGhosts - 1];
    return int(mostRecent.Result.Time);
}

int GetCurrNbGhosts() {
    auto dfm = GetApp().Network.ClientManiaAppPlayground.DataFileMgr;
    return dfm.Ghosts.Length;
}
