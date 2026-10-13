

#ifndef __G711_H__
#define __G711_H__

#ifdef __cplusplus
#if __cplusplus
extern "C" {
#endif
#endif /* __cplusplus */

int G711_EnCode(void* outBuffer, void* inBuffer, int nSize, int format);
int G711_Decode(char* outBuffer, const unsigned char* inBuffer, int nSize, int format);

#ifdef __cplusplus
#if __cplusplus
}
#endif
#endif /* __cplusplus */

#endif /* __G711_H__ */
