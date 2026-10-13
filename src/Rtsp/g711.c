#include <stdio.h>

  
#define	SIGN_BIT	(0x80)		/* Sign bit for a A-law byte. */
#define	QUANT_MASK	(0xf)		/* Quantization field mask. */
#define	NSEGS		(8)		/* Number of A-law segments. */
#define	SEG_SHIFT	(4)		/* Left shift for segment number. */
#define	SEG_MASK	(0x70)		/* Segment field mask. */	 

static short seg_aend[8] = {0x1F, 0x3F, 0x7F, 0xFF,
			    0x1FF, 0x3FF, 0x7FF, 0xFFF};
static short seg_uend[8] = {0x3F, 0x7F, 0xFF, 0x1FF,
			    0x3FF, 0x7FF, 0xFFF, 0x1FFF};
 
static short search(
   short val,
   short *table,
   short size)
{
   short i;
   
   for (i = 0; i < size; i++) {
      if (val <= *table++)
	 return (i);
   }
   return (size);
}

/*
 * linear2alaw() - Convert a 16-bit linear PCM value to 8-bit A-law
 *
 * linear2alaw() accepts an 16-bit integer and encodes it as A-law data.
 *
 *		Linear Input Code	Compressed Code
 *	------------------------	---------------
 *	0000000wxyza			000wxyz
 *	0000001wxyza			001wxyz
 *	000001wxyzab			010wxyz
 *	00001wxyzabc			011wxyz
 *	0001wxyzabcd			100wxyz
 *	001wxyzabcde			101wxyz
 *	01wxyzabcdef			110wxyz
 *	1wxyzabcdefg			111wxyz
 */
static unsigned char
linear2alaw(short pcm_val)	 
{
   short	 mask;
   short	 seg;
   unsigned char aval;
   
   pcm_val = pcm_val >> 3;

   if (pcm_val >= 0) {
      mask = 0xD5;		 
   } else {
      mask = 0x55;		 
      pcm_val = -pcm_val - 1;
   }
   
  
   seg = search(pcm_val, seg_aend, 8);
     
   if (seg >= 8)		 
      return (unsigned char) (0x7F ^ mask);
   else {
      aval = (unsigned char) seg << SEG_SHIFT;
      if (seg < 2)
	 aval |= (pcm_val >> 1) & QUANT_MASK;
      else
	 aval |= (pcm_val >> seg) & QUANT_MASK;
      return (aval ^ mask);
   }
}

/*
 * alaw2linear() - Convert an A-law value to 16-bit linear PCM
 *
 */
static short
alaw2linear(
   unsigned char	a_val)
{
   short t;
   short seg;
   
   a_val ^= 0x55;
   
   t = (a_val & QUANT_MASK) << 4;
   seg = ((unsigned)a_val & SEG_MASK) >> SEG_SHIFT;
   switch (seg) {
   case 0:
      t += 8;
      break;
   case 1:
      t += 0x108;
      break;
   default:
      t += 0x108;
      t <<= seg - 1;
   }
   return ((a_val & SIGN_BIT) ? t : -t);
}

#define	BIAS		(0x84)		 
#define CLIP            8159

/*
* linear2ulaw() - Convert a linear PCM value to u-law
*	Biased Linear Input Code	Compressed Code
*	------------------------	---------------
*	00000001wxyza			000wxyz
*	0000001wxyzab			001wxyz
*	000001wxyzabc			010wxyz
*	00001wxyzabcd			011wxyz
*	0001wxyzabcde			100wxyz
*	001wxyzabcdef			101wxyz
*	01wxyzabcdefg			110wxyz
*	1wxyzabcdefgh			111wxyz
* Each biased linear code has a leading 1 which identifies the segment
* number. The value of the segment number is equal to 7 minus the number
* of leading 0's. The quantization interval is directly available as the
* four bits wxyz.  * The trailing bits (a - h) are ignored.
*
* Ordinarily the complement of the resulting code word is used for
* transmission, and so the code word is complemented before it is returned.
*/
static unsigned char
linear2ulaw(
   short pcm_val)	 
{
   short         mask;
   short	 seg;
   unsigned char uval;
   
   
   pcm_val = pcm_val >> 2;
   if (pcm_val < 0) {
      pcm_val = -pcm_val;
      mask = 0x7F;
   } else {
      mask = 0xFF;
   }
   if ( pcm_val > CLIP ) pcm_val = CLIP;		 
   pcm_val += (BIAS >> 2);
   
  
   seg = search(pcm_val, seg_uend, 8);
   
  
   if (seg >= 8)		 
      return (unsigned char) (0x7F ^ mask);
   else {
      uval = (unsigned char) (seg << 4) | ((pcm_val >> (seg + 1)) & 0xF);
      return (uval ^ mask);
   }
   
}


/*
 * ulaw2linear() - Convert a u-law value to 16-bit linear PCM

 */
static short
ulaw2linear(
   unsigned char	u_val)
{
   short t;
   
   u_val = ~u_val;
     
   t = ((u_val & QUANT_MASK) << 3) + BIAS;
   t <<= ((unsigned)u_val & SEG_MASK) >> SEG_SHIFT;
   
   return ((u_val & SIGN_BIT) ? (BIAS - t) : (t - BIAS));
}

 
 /*
  G711_EnCode
   Parameters:
	  outBuffer  [OUT] g711 data
	  inBuffer   [IN] pcm  data
	  nSize     size of inBuffer
	  format=0 alaw ; format=1 ulaw       
   Returns
    G711 data size 
 */ 
int  G711_EnCode( void* outBuffer,
				  void* inBuffer, int nSize,int format)  
{
    if(outBuffer==NULL || inBuffer==NULL) return -1 ;

	short* src = (short*)inBuffer;  
    char* dst = (char*)outBuffer;
    int i;
	for(i=0; i<nSize/2; i++)  
	{   
		if(format==0)
		   
		   *dst++= linear2alaw(*src++) ;
		else
           
		   *dst++ =linear2ulaw(*src++);
	}  
	return (nSize/2); 
}  
 
  /*
 G711_Decode
  Parameters:
	  outBuffer   [OUT] pcm data
	  inBuffer    [IN] g711 data
	  nSize     size of inBuffer
	  format=0 alaw ; format=1 ulaw 
  Returns:
	pcm data size 
*/
int  G711_Decode( char* outBuffer,
				  const unsigned char* inBuffer , int nSize,int format)  
{
    if(outBuffer==NULL || inBuffer==NULL) return -1 ;

	short *out_data = (short*)outBuffer;  
    int i;
	for(i=0; i<nSize; i++)  
	{
		if(format==0) {
		   *out_data++ =alaw2linear(*inBuffer++);
		}
        else {
		   *out_data++ =ulaw2linear(*inBuffer++);
        }
	}  
	return (nSize*2); 
}  


 
