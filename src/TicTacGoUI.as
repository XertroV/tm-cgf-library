/*



*/


class TicTacGoUI {
    TicTacGo@ ttg;

    NvgButton@ moveBtn;
    NvgButton@ resizeBtn;
    NvgButton@[] buttons;

    vec2 windowPos;
    vec2 windowSize;
    float windowRatio = 1.6;

    TicTacGoUI(TicTacGo@ ttg) {
        @this.ttg = ttg;
        windowPos = GameWindowSize / 8.;
        windowSize = GameWindowSize / 2.;
        windowSize.y = windowSize.x / windowRatio;
        @moveBtn = NvgButton(vec2(), vec2(50, 50), Icons::Arrows);
        @moveBtn.onDrag = ButtonOnDrag(OnMoveBtnDrag);
        @resizeBtn = NvgButton(vec2(), vec2(50, 50), Icons::Expand);
        @resizeBtn.onDrag = ButtonOnDrag(OnResizeBtnDrag);
        buttons.InsertLast(moveBtn);
        buttons.InsertLast(resizeBtn);
        UpdatePositions();
        print(tostring(windowSize));
        print(tostring(windowPos));
    }

    vec2 get_GameWindowSize() {
        return vec2(Draw::GetWidth(), Draw::GetHeight());
    }

    float get_EdgePadding() {
        return windowSize.y * 0.04;
    }

    void UpdatePositions() {
        SetResizeBtnPos();
        SetMoveBtnPos();
    }

    void SetMoveBtnPos() {
        vec2 pos = windowPos;
        pos.x += windowSize.x; // TR
        pos += vec2(-EdgePadding * 2., EdgePadding); // TR - Pad
        pos.x -= moveBtn.size.x - resizeBtn.size.x; // Btn TL
        moveBtn.pos = pos;
    }

    void SetResizeBtnPos() {
        vec2 pos = windowPos;
        pos.x += windowSize.x; // TR
        pos += vec2(-EdgePadding, EdgePadding); // TR - Pad
        pos.x -= resizeBtn.size.x; // Btn TL
        resizeBtn.pos = pos;
    }

    void OnMoveBtnDrag(NvgButton@ btn) {
        // center of move btn;
        vec2 mp = g_LastMousePos;
        mp += vec2(1, -1) * moveBtn.size / 2.; // TR btn
        mp += vec2(resizeBtn.size.x + EdgePadding * 2., -EdgePadding); // TR window
        windowPos = mp - vec2(windowSize.x, 0);
    }

    void OnResizeBtnDrag(NvgButton@ btn) {
        // center of resize btn
        vec2 mp = g_LastMousePos;
        mp += vec2(1, -1) * resizeBtn.size / 2.; // TR btn
        mp += vec2(EdgePadding, -EdgePadding); // TR window
        // mp.y += windowSize.y; // BR window
        vec2 expected = windowPos + vec2(0, windowSize.y);
        // difference between expected and mp will tell us how to mod pos and size
        auto diff = expected - mp;
        windowPos.y -= diff.y;
        windowSize.y += diff.y;
        windowSize.x = windowSize.y / windowRatio;
    }


    // call to draw the game
    void Render() {
        if (!CurrentlyInMap) {
            RenderGameUI();
            return;
        }
    }

    void RenderGameUI() {
        nvg::Reset();
        DrawBackground();
        for (uint i = 0; i < buttons.Length; i++) buttons[i].Draw();
    }

    vec4 bgColor = vec4(0, 0, 0, .9);

    void DrawBackground() {
        nvg::BeginPath();
        nvg::Rect(windowPos, windowSize);
        nvg::FillColor(bgColor);
        nvg::Fill();
        nvg::ClosePath();
    }

    vec4 btnChallengeCol = vec4(.8, .4, 0, 1);
    vec4 btnWinningCol = vec4(.8, .4, 0, 1);

    bool _SquareButton(const string &in id, vec2 size, int col, int row, bool isBeingChallenged, bool  ownedByMe, bool ownedByThem, bool isWinning) {
        if (isBeingChallenged) {
            UI::PushStyleColor(UI::Col::Button, btnChallengeCol);
        }
        if (isWinning) {
            UI::PushStyleColor(UI::Col::Button, btnWinningCol);
        }
        bool clicked = UI::Button(id, size);
        bool isHovered = UI::IsItemHovered();
        if (isBeingChallenged) UI::PopStyleColor(1);
        if (isWinning) UI::PopStyleColor(1);
        if (isHovered) {
            UI::BeginTooltip();
            UI::PushFont(hoverUiFont);

            if (ownedByMe) {
                // button disabled so never hovers
                // UI::Text("(You already claimed this square)");
            } else if (ownedByThem) {
                UI::Text("Challenge " + ttg.OpponentsName);
                UI::Separator();
                auto map = ttg.GetMap(col, row);
                int tid = map['TrackID'];
                UI::Text(ColoredString(map['Name']));
                UI::Text(map['LengthName']);
                UI::Text(map['DifficultyName']);
                ttg.DrawThumbnail(tostring(tid), 256);
            } else {
                UI::Text("Mystery Map.\nWin a race to claim!\n(Stays unclaimed otherwise.)");
            }

            UI::PopFont();
            UI::EndTooltip();
        }
        return clicked;
    }

    /* MOUSE STUFF */

    // the last position of the mouse, updated on mouse move
    vec2 g_LastMousePos;

    /** Called whenever the mouse moves. `x` and `y` are the viewport coordinates.
    */
    void OnMouseMove(int x, int y) {
        vec2 pos = vec2(x, y);
        print(tostring(pos));
        g_LastMousePos = pos;
        for (uint i = 0; i < buttons.Length; i++) {
            buttons[i].UpdateMouse(pos);
        }
    }

    /** Called whenever a mouse button is pressed. `x` and `y` are the viewport coordinates.
    */
    UI::InputBlocking OnMouseButton(bool down, int button, int x, int y) {
        if (!ttg.client.IsInGame) return UI::InputBlocking::DoNothing;
        bool isLeftBtn = button == 0;
        if (!isLeftBtn) return UI::InputBlocking::DoNothing;
        auto mousePos = vec2(x, y);
        g_LastMousePos = mousePos;
        bool blockClick = false;
        for (uint i = 0; i < buttons.Length; i++) {
            blockClick = blockClick || (!down && buttons[i].IsClicked); // releasing a clicked button
            auto hovered = buttons[i].UpdateMouse(mousePos, down ? MouseUpdateClick::Down : MouseUpdateClick::Up);
            blockClick = blockClick || (down && hovered); // clicking a button
        }
        return blockClick ? UI::InputBlocking::Block : UI::InputBlocking::DoNothing;
    }
}
