const string c_reset = "\\$z";
const string c_green = "\\$3f0";
const string c_brightBlue = "\\$1bf";
const string c_debug = c_brightBlue;
const string c_mid_grey = "\\$777";
const string c_dark_grey = "\\$333";
const string c_orange_600 = "\\$f61";
const string c_green_700 = "\\$3a3";
const string c_fuchsia = "\\$f19";
const string c_purple = "\\$a4f";

const string c_timeOrange = "\\$d81";
const string c_timeBlue = "\\$3ce";

const string c_warn = "\\$fd2";



void dev_print(const string &in msg) {
#if DEV
    print(msg);
#endif
}

enum LogLevel {
    Error = 0,
    Warn = 1,
    Info = 2,
    Debug = 3,
    Trace = 4
}

// disable this setting for the moment b/c it doesn't do much
[Setting category="General" name="Log Level" description="How verbose should the logs be? (Note: currently Error and Warning msgs will always be shown, regardless of this setting)"]
LogLevel Setting_LogLevel = LogLevel::Trace;

void debug(const string &in text) {
    log_debug(c_debug + text);
}

void log_debug(const string &in msg) {
    if (Setting_LogLevel >= LogLevel::Debug)
        print(msg);
}

void log_dev(const string &in text) {
#if DEV
    print(c_green + text);
#endif
}

void logcall(const string &in caller, const string &in text) {
    log_info(c_mid_grey + "[" + c_debug + caller + c_mid_grey + "] " + text);
}

void logcall_trace(const string &in caller, const string &in text) {
    log_trace(c_mid_grey + "[" + c_debug + caller + c_mid_grey + "] " + text);
}

void dev_logcall(const string &in caller, const string &in text) {
#if DEV
    logcall(caller, text);
#endif
}

void todo(const string &in text) {
    if (Setting_LogLevel >= LogLevel::Info)
        print(c_orange_600 + "todo: " + c_green_700 + text);
}

void trace_benchmark(const string &in action, uint deltaMs) {
    log_trace(c_mid_grey + "[" + c_purple + action + c_mid_grey + "] took " + c_purple + deltaMs + " ms");
}

void trace_benchmark_(const string &in action, uint start) {
    auto deltaMs = Time::Now - start;
    log_trace(c_mid_grey + "[" + c_purple + action + c_mid_grey + "] took " + c_purple + deltaMs + " ms");
}

void trace_dev(const string &in msg) {
#if DEV
    log_trace(msg);
#endif
}

void log_trace(const string &in msg) {
    if (Setting_LogLevel >= LogLevel::Trace) {
        trace(msg);
    }
}

void log_info(const string &in msg) {
    if (Setting_LogLevel >= LogLevel::Info) {
        print(msg);
    }
}

void log_warn(const string &in msg) {
    if (Setting_LogLevel >= LogLevel::Warn) {
        warn(msg);
    }
}

void log_error(const string &in msg) {
    if (Setting_LogLevel >= LogLevel::Error) {
        error(msg);
    }
}
