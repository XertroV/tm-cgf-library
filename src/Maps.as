
const string MapThumbUrl(Json::Value@ map) {
    if (!bool(map['HasThumbnail'])) return "";
    return "https://trackmania.exchange/maps/thumbnail/" + int(map['TrackID']);
}

const string MapUrl(Json::Value@ map) {
    int trackId = map['TrackID'];
    return "https://cgf.s3.nl-1.wasabisys.com/" + trackId + ".Map.Gbx";
}

const string MapUrlTmx(int TrackID) {
    return "https://trackmania.exchange/maps/download/" + TrackID;
}



void LoadMapNow(const string &in url) {
    if (!Permissions::PlayLocalMap()) {
        NotifyError("Refusing to load map because you lack the necessary permissions. Standard or Club access required");
        return;
    }
    ReturnToMenu();
    AwaitManialinkTitleReady();
    auto app = cast<CGameManiaPlanet>(GetApp());
    app.ManiaTitleControlScriptAPI.PlayMap(url, "", "");
}

void ReturnToMenu() {
    auto app = cast<CGameManiaPlanet>(GetApp());
    app.BackToMainMenu();
}

void AwaitManialinkTitleReady() {
    auto app = cast<CGameManiaPlanet>(GetApp());
    while (!app.ManiaTitleControlScriptAPI.IsReady) yield();
}

bool HasJoinLinkPermissions() {
    return Permissions::PlayPublicClubRoom() && Permissions::PlayPrivateActivity();
}

void LoadJoinLink(const string &in joinLink) {
    if (!HasJoinLinkPermissions()) {
        NotifyError("Refusing to load join link because you lack 1 or more of the permission: PlayPublicClubRoom, PlayPrivateActivity.");
        return;
    }
    auto app = cast<CTrackMania>(GetApp());
    // app.Network.ServerInfo
    string serverLogin = cast<CTrackManiaNetworkServerInfo>(app.Network.ServerInfo).ServerLogin;
    bool alreadyInServer = app.CurrentPlayground !is null && serverLogin != "" && joinLink.Contains("join=" + serverLogin);
    if (!alreadyInServer) {
        ReturnToMenu();
        yield();
        AwaitManialinkTitleReady();
        yield();
        app.ManiaPlanetScriptAPI.OpenLink(joinLink.Replace("#join", "#qjoin"), CGameManiaPlanetScriptAPI::ELinkType::ManialinkBrowser);
        yield();
    } else {
        trace("LoadJoinLink: already in that server.");
    }
}


void EnsureMapsHelper(Json::Value@ map_tids_uids) {
    string[] uids;
    MwFastBuffer<wstring> mapUidList = MwFastBuffer<wstring>();
    int[] tids;
    for (uint i = 0; i < map_tids_uids.Length; i++) {
        tids.InsertLast(int(map_tids_uids[i][0]));
        mapUidList.Add(string(map_tids_uids[i][1]));
        uids.InsertLast(string(map_tids_uids[i][1]));
    }
    auto app = cast<CGameManiaPlanet>(GetApp());
    auto cma = app.MenuManager.MenuCustom_CurrentManiaApp;
    auto dfm = cma.DataFileMgr;
    auto getMaps = dfm.Map_NadeoServices_GetListFromUid(cma.UserMgr.Users[0].Id, mapUidList);
    while (getMaps.IsProcessing) yield();
    if (getMaps.HasFailed) {
        NotifyError("Failed to get map info from nadeo: " + getMaps.ErrorCode + ", " + getMaps.ErrorType + ", " + getMaps.ErrorDescription);
        return;
    }
    if (getMaps.IsCanceled) {
        NotifyError("Get maps info from nadeo was canceled. :(");
        return;
    }
    if (!getMaps.HasSucceeded) {
        throw("EnsureMapsHelper unknown state! not processing, not failed, not success. ");
    }

    for (uint i = 0; i < getMaps.MapList.Length; i++) {
        auto item = getMaps.MapList[i];
        auto ix = uids.Find(item.Uid);
        if (ix >= 0) {
            uids.RemoveAt(ix);
            tids.RemoveAt(ix);
        }
    }
    // uids and tids are now only unknown maps
    if (uids.IsEmpty()) return;

    if (!Permissions::CreateAndUploadMap()) {
        NotifyError("Refusing to upload maps because you are missing the CreateAndUploadMap permissions.");
        return;
    }

    ReturnToMenu();

    warn("Getting maps that aren't uploaded to nadeo services: " + string::Join(uids, ", "));
    // request all the maps
    Meta::PluginCoroutine@[] coros;
    for (uint i = 0; i < uids.Length; i++) {
        auto uid = uids[i];
        auto tid = tids[i];
        auto coro = startnew(DownloadMapAndUpload, DlMapAndUploadData(uid, tid));
        coros.InsertLast(coro);
    }
    await(coros);
    warn("Finished uploading maps.");
}

void DownloadMapAndUpload(ref@ data) {
    DlMapAndUploadData@ pl = cast<DlMapAndUploadData>(data);
    if (pl is null) {
        warn("DownloadMapAndUpload got a null payload!");
        return;
    }
    if (!IsMapUploadedToNadeo(pl.uid)) {
        DownloadTmxMapToLocal(pl.tid);
        UploadMapFromLocal(pl.uid);
    }
}

class DlMapAndUploadData {
    int tid;
    string uid;
    DlMapAndUploadData(const string &in uid, int tid) {
        this.tid = tid;
        this.uid = uid;
    }
}

// Ends in a slash
const string GetLocalTmxMapFolder() {
    return IO::FromUserGameFolder('Maps/CGF-TMX/');
}

const string GetLocalTmxMapPath(int TrackID) {
    auto tmxFolder = GetLocalTmxMapFolder();
    if (!IO::FolderExists(tmxFolder))
        IO::CreateFolder(tmxFolder, true);
    return tmxFolder + TrackID + '.Map.Gbx';
}

void DownloadTmxMapToLocal(int TrackID) {
    string url = MapUrlTmx(TrackID);
    auto req = PluginGetRequest(url);
    req.Start();
    while (!req.Finished()) yield();
    // todo
    if (req.ResponseCode() >= 400) {
        warn("Error downloading TMX map to local: " + req.Error());
    } else {
        auto outFile = GetLocalTmxMapPath(TrackID);
        req.SaveToFile(outFile);
        trace('Saved tmx map ' + TrackID + ' to ' + outFile);
    }
}

// this shouldn't be necessary that often, and ppl can manually clear (or we can clean up on plugin load or something)
// void RemoveTmxMapFromLocal(int TrackID) {
//     auto outFile = GetLocalTmxMapPath(TrackID);
// }

void UploadMapFromLocal(const string &in uid) {
    if (!Permissions::CreateAndUploadMap()) {
        NotifyError("Refusing to upload maps because you are missing the CreateAndUploadMap permissions.");
        return;
    }
    trace('UploadMapFromLocal: ' + uid);
    auto app = cast<CGameManiaPlanet>(GetApp());
    auto cma = app.MenuManager.MenuCustom_CurrentManiaApp;
    auto dfm = cma.DataFileMgr;
    auto userId = cma.UserMgr.Users[0].Id;
    // back to menu so we can refresh maps
    app.BackToMainMenu();
    while (!app.ManiaTitleControlScriptAPI.IsReady) yield();
    // Do not run from within a map; will cause a script error (Map.MapInfo.MapUid is undefined, and lots of angelscript exceptions, too)
    dfm.Map_RefreshFromDisk();
    trace('UploadMapFromLocal: refreshed maps, attempting upload');
    yield();
    auto regScript = dfm.Map_NadeoServices_Register(userId, uid);
    while (regScript.IsProcessing) yield();
    if (regScript.HasFailed) {
        warn("UploadMapFromLocal: Uploading map failed: " + regScript.ErrorType + ", " + regScript.ErrorCode + ", " + regScript.ErrorDescription);
        return;
    }
    if (regScript.HasSucceeded) {
        trace("UploadMapFromLocal: Map uploaded: " + uid);
    }
}

bool IsMapUploadedToNadeo(const string &in uid) {
    auto cma = cast<CGameManiaPlanet>(GetApp()).MenuManager.MenuCustom_CurrentManiaApp;
    auto dfm = cma.DataFileMgr;
    auto userId = cma.UserMgr.Users[0].Id;
    auto getFromUid = dfm.Map_NadeoServices_GetFromUid(userId, uid);
    while (getFromUid.IsProcessing) yield();
    if (getFromUid.HasSucceeded) {
        if (getFromUid.Map is null) {
            trace('get map success but null map');
            return false;
        } else {
            trace('get map success: ' + getFromUid.Map.Name + ", " + getFromUid.Map.FileUrl);
            return true;
        }
    }
    if (getFromUid.ErrorDescription.Contains("Unknown map")) {
        return false;
    }
    warn('get from uid did not succeed: ' + getFromUid.ErrorType + ", " + getFromUid.ErrorCode + ", " + getFromUid.ErrorDescription);
    return false;
}

#if DEV
// seems to work!
void MapUploadTest() {
    // string testUid = "m9hkGQKexEG1wB9IzpdvaIt3wu4";
    string testUid = "xpZkdT35kAABq4h7Ju4e5bnbWlc";
    trace('before: IsMapUploaded ' + testUid + ": " + tostring(IsMapUploadedToNadeo(testUid)));
    if (!IsMapUploadedToNadeo(testUid)) {
        DownloadTmxMapToLocal(72318);
        UploadMapFromLocal(testUid);
        trace('after: IsMapUploaded ' + testUid + ": " + tostring(IsMapUploadedToNadeo(testUid)));
    }
    // if (IsMapUploadedToNadeo(testUid)) {
    //     // RemoveTmxMapFromLocal(72318);
    // }
}
#endif
