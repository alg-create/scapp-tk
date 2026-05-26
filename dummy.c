#include <stdio.h>
#include <assert.h>
#include <stdlib.h>

#define WEAK __attribute__((weak))
#define MAGIC 25620

enum UndefinedAction {
    UFAIL,
    USUCCEED,
    UABORT
};

enum Functions {
    FUNCTION_ONE,
    FUNCTION_TWO,

    FUNCTION_MAX
};

typedef int (*const JumpFunction)(...);
typedef JumpFunction JumpTable[FUNCTION_MAX];

int FunctionOne(void) WEAK;
int FunctionTwo(int) WEAK;

static enum UndefinedAction g_uaction = UFAIL;

static int DummyFunction(...) {
    switch (g_uaction) {
        case UFAIL:
            return -1;
        case USUCCEED:
            return 0;
        case UABORT:
            abort();
    }
    return -1;
}

static JumpFunction g_jump_fallback_table[] = {
    [FUNCTION_ONE] = DummyFunction,
    [FUNCTION_TWO] = DummyFunction
};

static JumpTable *g_jump_table = &g_jump_fallback_table;

int Init(const int magic, const enum UndefinedAction uaction, JumpTable* const f) {
    assert(magic == MAGIC);
    assert(uaction >= UFAIL);
    assert(uaction <= UABORT);
    assert(f != NULL);
    g_uaction = uaction;
    g_jump_table = f;
    return 0;
}

int Main(void) {
    puts("Hello World");
    FunctionOne();
    FunctionTwo(42);
    return 0;
}

static JumpFunction get_jump_function(const size_t index) {
    assert(index < (sizeof g_jump_fallback_table / sizeof g_jump_fallback_table[0]));
    return (*g_jump_table)[index] ? (*g_jump_table)[index] : g_jump_fallback_table[index];
}

int FunctionOne(void) {
    return get_jump_function(FUNCTION_ONE)();
}

int FunctionTwo(const int x) {
    return get_jump_function(FUNCTION_TWO)(x);
}
