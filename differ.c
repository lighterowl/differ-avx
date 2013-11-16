#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <sys/mman.h>
#include "differ.h"

#define PRECISION 5000007
#define ITERS 10000

inline unsigned long long rdtsc(void)
{
  unsigned long long retval;
  asm volatile (
    "xorl %%eax, %%eax\n\t"
    "cpuid\n\t"
    "rdtsc\n\t"
    "shlq $32, %%rdx\n\t"
    "orq %%rdx, %%rax\n\t"
    : "=a"(retval)
    :
    : "%rbx", "%rcx", "%rdx"
  );
  return retval;
}

inline float randf(void) { return rand() / (float)RAND_MAX; }

void randomize_args(struct differ_args *a)
{
  a->start = randf() * ((rand() % 64) - 32);
  a->end = randf() * ((rand() % 128) + 96);
  a->a = randf() * ((rand() % 10) - 5);
  a->b = randf() * ((rand() % 20) - 10);
  a->c = randf() * ((rand() % 40) - 20);
}

int main(void)
{
  struct differ_args args;
  unsigned int i;
  unsigned long long pre,post,sum = 0;
  
  srand((unsigned int)rdtsc());
  
  args.N = PRECISION;
#ifdef USE_MALLOC
  args.dest = malloc(PRECISION*sizeof(*args.dest));
  if(args.dest == NULL) return 1;
#elif defined USE_MMAP
  args.dest = mmap(NULL,PRECISION*sizeof(*args.dest),PROT_READ | PROT_WRITE,
    MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
  if(args.dest == MAP_FAILED)
  {
    perror("mmap()");
    return 1;
  }
#else
#error "Please define either USE_MALLOC or USE_MMAP"
#endif
  
  for(i=0;i<ITERS;++i)
  {
    randomize_args(&args);
    pre = rdtsc();
    differentiate(&args);
    post = rdtsc();
    sum += post-pre;
  }
  printf("%llu\n",sum / ITERS);
  /*for(i=0;i<args.N;++i) printf("%f\n",args.dest[i]);*/
  
#ifdef USE_MALLOC
  free(args.dest);
#elif defined USE_MMAP
  munmap(args.dest,PRECISION*sizeof(*args.dest));
#endif
  return 0;
}
