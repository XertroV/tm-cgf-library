void NvgTextWShadow(vec2 pos, float dist, const string &in text, vec4 textColor) {
    vec2 offs = vec2(dist, dist);
    nvg::FillColor(vec4(0, 0, 0, 1));
    nvg::Text(pos + offs, text);
    nvg::FillColor(textColor);
    nvg::Text(pos, text);
}


const string TimeFormat(int time, bool fractions = true, bool forceMinutes = true, bool forceHours = false, bool short = false) {
    return (time < 0 ? "-" : "") + Time::Format(time, fractions, forceMinutes, forceHours, short);
}
