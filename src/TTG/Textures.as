UI::Texture@ p1Texture = null;
UI::Texture@ p2Texture = null;

void LoadTextures() {
    if (p1Texture !is null) return;
    @p1Texture = UI::LoadTexture("img/o.png");
    @p2Texture = UI::LoadTexture("img/x.png");
}
