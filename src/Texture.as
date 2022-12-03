class CGF_Texture {
    UI::Texture@ ui;
    nvg::Texture@ nvg;

    CGF_Texture(MemoryBuffer &in buf) {
        buf.Seek(0);
        @ui = UI::LoadTexture(buf);
        buf.Seek(0);
        @nvg = nvg::LoadTexture(buf);
    }
}
