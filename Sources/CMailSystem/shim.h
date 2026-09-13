#include <libxml2/libxml/HTMLparser.h>
#include <libxml2/libxml/tree.h>
#include <resolv.h>
#include <arpa/nameser.h>
#include <string.h>

// libxml2's allocator pointer is never modified by Transorma.
static inline void transorma_xml_free(void *pointer) { xmlFree(pointer); }

// A private resolver state avoids the global res_query state when Mail invokes us concurrently.
static inline int transorma_query_txt(const char *name, char *output, size_t capacity) {
    struct __res_state state;
    memset(&state, 0, sizeof(state));
    if (res_ninit(&state) != 0) return -1;
    state.retrans = 2;
    state.retry = 1;
    unsigned char packet[65536];
    int length = res_nquery(&state, name, ns_c_in, ns_t_txt, packet, sizeof(packet));
    res_nclose(&state);
    if (length <= 0 || length > sizeof(packet)) return -1;
    ns_msg message;
    if (ns_initparse(packet, length, &message) < 0) return -1;
    size_t offset = 0;
    for (int i = 0; i < ns_msg_count(message, ns_s_an); i++) {
        ns_rr record;
        if (ns_parserr(&message, ns_s_an, i, &record) < 0) return -1;
        if (ns_rr_type(record) != ns_t_txt) continue;
        const unsigned char *data = ns_rr_rdata(record);
        size_t size = ns_rr_rdlen(record), index = 0;
        while (index < size) {
            size_t count = data[index++];
            if (index + count > size || offset + count + 1 >= capacity) return -1;
            for (size_t j = 0; j < count; j++) {
                if (data[index + j] < 32 || data[index + j] > 126) return -1;
            }
            memcpy(output + offset, data + index, count);
            offset += count;
            index += count;
        }
        output[offset++] = '\n';
    }
    return (int)offset;
}
