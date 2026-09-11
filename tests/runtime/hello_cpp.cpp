#include <cstdio>
#include <stdexcept>

struct Base { virtual ~Base() {} };
struct Derived : Base { int value = 42; };

int main()
{
    Base *b = new Derived;
    Derived *d = dynamic_cast<Derived *>(b);
    if (!d || d->value != 42)
        return 2;

    try {
        throw std::runtime_error("mogrix");
    } catch (const std::exception &e) {
        std::printf("mogrix C++ runtime OK: %s\n", e.what());
    }

    delete b;
    return 0;
}
