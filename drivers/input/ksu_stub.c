#include <linux/types.h>

#ifdef CONFIG_KSU
bool ksu_input_hook __read_mostly = false;
__attribute__((cold))
int ksu_handle_input_handle_event(unsigned int *type,
                                  unsigned int *code,
                                  int *value)
{
    /* Return 0 to indicate "no handling" — adjust if you need special behavior */
    return 0;
}
EXPORT_SYMBOL(ksu_input_hook);
EXPORT_SYMBOL(ksu_handle_input_handle_event);
#endif
