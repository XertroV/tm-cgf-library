

void dev_print(const string &in msg) {
#if DEV
    print(msg);
#endif
}
