// vec4 OP_COLOR = vec4(1, 0x33 / 0xff, 0x99 / 0xff, 1);
// vec4 OP_COLOR = vec4(1, 0.482, 0.793, 1);
vec4 OP_COLOR = vec4(1, 0.416, 0.757, 1);

void RenderHeartbeatPulse(vec2 centerPos, vec2 size) {
    nvg::Reset();
    float t = float(Time::Now) * 0.001 / 2. % 1;
    nvg::StrokeWidth(10);
    nvgHeartbeatPath(centerPos, size, t);
}

// std relative positions for a 270 * 164 sized box
vec2[] HeartbeatStdPath =
    { vec2(0, 0)
    , vec2(90, 0)
    , vec2(108, -60)
    , vec2(146, 44)
    , vec2(174, -28)
    , vec2(192, 0)
    , vec2(270, 0)
    };

float HB_GRADIENT_WIDTH = 0.15;

void nvgHeartbeatPath(vec2 centerPos, vec2 size, float t) {
    // rescale t to range from -.1 to 1.1 // todo: should be HB_GRADIENT_WIDTH
    t = t * (1 + 4. * HB_GRADIENT_WIDTH) - HB_GRADIENT_WIDTH * 2.;
    nvg::BeginPath();
    nvg::LineCap(nvg::LineCapType::Round);
    vec2 centerLeft = centerPos - vec2(size.x / 2., 0);
    vec2 posScale = size / vec2(270, 164);
    float swapXPoint = t * size.x;
    vec2 prior = vec2(-270.0 * HB_GRADIENT_WIDTH, 0) * posScale;
    nvg::Paint paint = calcHeartbeatPaint(centerPos, size, t, t > 0);
    auto initPos = HeartbeatStdPath[0] * posScale + centerLeft;
    nvg::MoveTo(initPos);
    // calc initial paint
    for (uint i = 1; i < HeartbeatStdPath.Length; i++) {
        auto nextPosRel = HeartbeatStdPath[i] * posScale;
        bool needMid = swapXPoint > 0 && prior.x <= swapXPoint && nextPosRel.x > swapXPoint;
        if (needMid) {
            auto r = (swapXPoint - prior.x) / (nextPosRel.x - prior.x);
            auto midPoint = (nextPosRel - prior) * r + prior;
            nvg::LineTo(midPoint + centerLeft);
            nvg::StrokePaint(paint);
            nvg::Stroke();
            nvg::ClosePath();
            nvg::BeginPath();
            nvg::MoveTo(midPoint + centerLeft);
            paint = calcHeartbeatPaint(centerPos, size, t, false);
        }
        prior = nextPosRel;
        auto nextPos = nextPosRel + centerLeft;
        nvg::LineTo(nextPos);
    }
    nvg::StrokePaint(paint);
    // nvg::StrokeWidth(10);
    nvg::Stroke();
    nvg::ClosePath();
}

nvg::Paint calcHeartbeatPaint(vec2 centerPos, vec2 size, float t, bool isLeft) {
    // on left hand side (trailing) we go from transparent to pink
    auto halfWidth = HB_GRADIENT_WIDTH * size.x / 2.;
    auto centerLeft = centerPos - vec2(size.x/2, 0);
    auto gradMidPointX = size.x * t + centerLeft.x - size.x * HB_GRADIENT_WIDTH;
    auto gradMidPoint = vec2(gradMidPointX, centerLeft.y);
    auto gradLeftPoint = gradMidPoint - vec2(halfWidth, 0);
    auto gradRightPoint = gradMidPoint + vec2(halfWidth, 0);

    if (isLeft) {
        return nvg::LinearGradient(gradLeftPoint, gradMidPoint, OP_COLOR * 0., OP_COLOR);
    } else {
        return nvg::LinearGradient(gradMidPoint, gradRightPoint, OP_COLOR, OP_COLOR * 0.);
    }
}
