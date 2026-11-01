int main(void) {
    volatile long long sum = 0;
    for (long long i = 1; i <= 20000000; ++i) {
        sum += i;
    }
    return (int)sum;
}
