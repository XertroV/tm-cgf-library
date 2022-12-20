Net::HttpRequest@ PluginGetRequest(const string &in url) {
    auto r = Net::HttpGet(url);
    r.Headers['User-Agent'] = "TM_Plugin:CommunityGameFramework / contact=@XertroV,cgf@xk.io / client_version=" + Meta::ExecutingPlugin().Version;
    return r;
}
