#ifndef _DIFFER_H
#define _DIFFER_H

struct differ_args
{
  float start, end; /* the start and end of the differentiated area. */
  unsigned int N; /* how many samples to take in the area. */
  float a,b,c; /* parameters of the quadratic function. */
  float *dest; /* address of the result array. this should point to an area of
  N*sizeof(*dest) bytes. */
};

void differentiate(struct differ_args*);

#endif /* _DIFFER_H */
