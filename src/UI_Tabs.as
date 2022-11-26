class Tab {
    bool canCloseTab = false;

    string tabName;

    Tab(const string &in tabName) {
        this.tabName = tabName;
    }

    int get_TabFlags() {
        return UI::TabItemFlags::NoCloseWithMiddleMouseButton
            | UI::TabItemFlags::NoReorder
            ;
    }

    void DrawTab() {
        if (UI::BeginTabItem(tabName, TabFlags)) {
            DrawInner();
            UI::EndTabItem();
        }
    }

    void DrawInner() {
        UI::Text("Tab Inner: " + tabName);
        UI::Text("Overload `DrawInner()`");
    }
}
