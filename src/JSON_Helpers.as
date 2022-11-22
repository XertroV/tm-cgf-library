Json::Value@ JsonObject1(const string &in key, Json::Value@ v) {
    auto j = Json::Object();
    j[key] = v;
    return j;
}

Json::Value@ JsonObject2(const string &in key, Json::Value@ v, const string &in key2, Json::Value@ v2) {
    auto j = Json::Object();
    j[key] = v;
    j[key2] = v2;
    return j;
}
