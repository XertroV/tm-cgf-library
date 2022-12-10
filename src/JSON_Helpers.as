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


const Json::Value@ EMPTY_JSON_OBJ = Json::Object();


bool IsJsonArray(Json::Value@ j) {
    if (j is null) return false;
    return j.GetType() == Json::Type::Array;
}

bool IsJsonObject(Json::Value@ j) {
    if (j is null) return false;
    return j.GetType() == Json::Type::Object;
}

bool IsJsonString(Json::Value@ j) {
    if (j is null) return false;
    return j.GetType() == Json::Type::String;
}



void JsonCheckbox(const string &in label, Json::Value@ jsonObj, const string &in key, bool _default) {
    bool tmp = jsonObj.Get(key, _default);
    tmp = UI::Checkbox(label, tmp);
    jsonObj[key] = tmp;
}
