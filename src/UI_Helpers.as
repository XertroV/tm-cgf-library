void PaddedSep(float scale=1.0) {
    UI::Dummy(vec2(0, 6. * scale));
    UI::Separator();
    UI::Dummy(vec2(0, 6. * scale));
}

void TextSameLine(const string &in msg) {
    UI::Text(msg);
    UI::SameLine();
}

void Indent(float n = 1) {
    UI::Dummy(vec2(4 * n, 0));
    UI::SameLine();
}




bool DrawHeading1Button(const string &in heading, const string &in btnLabel) {
    UI::PushFont(mapUiFont);
    // UI::Text("Lobby");
    bool ret = false;
    if (UI::BeginTable("ttg-heading"+heading, 2, UI::TableFlags::SizingFixedFit)) {
        UI::TableSetupColumn("l", UI::TableColumnFlags::WidthStretch);
        UI::TableNextRow();
        UI::TableNextColumn();
        UI::AlignTextToFramePadding();
        UI::Text(heading);
        UI::TableNextColumn();
        ret = UI::Button(btnLabel);
        UI::EndTable();
    }
    UI::PopFont();
    UI::Separator();
    return ret;
}


bool DrawSubHeading1Button(const string &in heading, const string &in btnLabel) {
    UI::PushFont(hoverUiFont);
    // UI::Text("Lobby");
    bool ret = false;
    if (UI::BeginTable("ttg-heading"+heading, 2, UI::TableFlags::SizingFixedFit)) {
        UI::TableSetupColumn("l", UI::TableColumnFlags::WidthStretch);
        UI::TableNextRow();
        UI::TableNextColumn();
        UI::AlignTextToFramePadding();
        UI::Text(heading);
        UI::TableNextColumn();
        ret = UI::Button(btnLabel);
        UI::EndTable();
    }
    UI::PopFont();
    UI::Separator();
    return ret;
}



bool TtgCollapsingHeader(const string &in label) {
    UI::PushStyleColor(UI::Col::Header, vec4(0, 0, 0, 0));
    UI::PushStyleColor(UI::Col::HeaderHovered, vec4(.3, .9, .6, .2));
    UI::PushStyleColor(UI::Col::HeaderActive, vec4(.3, .9, .6, .1));
    bool open = UI::CollapsingHeader(label);
    UI::PopStyleColor(3);
    return open;
}
