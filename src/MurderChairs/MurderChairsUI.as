class MurderChairsUI {
    MurderChairsState@ state;

    void RenderUpdate(float dt) {
        // for game events
        vec2 pos = GameEventsTopLeft;
        // draw maps along top
        // draw game events
        float yDelta = BaseFontHeight + EventLogSpacing;
        for (int i = 0; i < int(state.activeEvents.Length); i++) {
            if (state.activeEvents[i].RenderUpdate(dt, pos)) {
                state.activeEvents.RemoveAt(i);
                i--;
            } else {
                pos.y += yDelta;
            }
        }
    }
}

vec2 GameEventsTopLeft {
    get {
        float h = Draw::GetHeight();
        float w = Draw::GetWidth();
        float hOffset = 0;
        float idealWidth = 1.7777777777777777 * h;
        if (w < idealWidth) {
            float newH = w / 1.7777777777777777;
            hOffset = (h - newH) / 2.;
            h = newH;
        }
        if (UI::IsOverlayShown()) hOffset += 24;
        float wOffset = (float(Draw::GetWidth()) - (1.7777777777777777 * h)) / 2.;
        vec2 tl = vec2(wOffset, hOffset) + vec2(h * 0.15, w * 0.025);
        return tl;
    }
}
