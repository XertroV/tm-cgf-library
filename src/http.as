Net::HttpRequest@ PluginGetRequest(const string &in url) {
    auto r = Net::HttpRequest();
    r.Url = url;
    r.Method = Net::HttpMethod::Get;
    r.Headers['User-Agent'] = "TM_Plugin:TicTacGo / contact=@XertroV,cgf@xk.io / client_version=" + Meta::ExecutingPlugin().Version;
    return r;
}
