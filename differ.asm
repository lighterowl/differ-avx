BITS 64

SECTION .data
; constants, since AVX doesn't allow immediate operands
packed_8 times 8 dd 8.0
minus_1 dd -1.0

%USE smartalign
alignmode p6

SECTION .text

GLOBAL differentiate
differentiate:
; void differentiate(struct differ_args* : rdi);
  push  rbp
  mov   rbp,  rsp
  and   rsp,  ~31 ; align the stack to 32 bytes
  sub   rsp,  64 ; reserve space for 2 ymmwords = 64 bytes

  vmovss      xmm0, [rdi+4]
  vsubss      xmm0, [rdi]
  vcvtsi2ss   xmm1, [rdi+8]
  vdivss      xmm0, xmm1 ; xmm0 <= ((end-start)/N) = dx (size of a single step)
  vmovss      xmm1, xmm0 ; xmm1 <= dx
  vmovss      xmm2, xmm0 ; xmm2 <= dx
  vmovss      xmm3, xmm0 ; xmm3 <= dx
  vmovss      xmm12,xmm0 ; xmm12 <= dx (for the single-element loop later on)
  vmulss      xmm1, [minus_1] ; xmm1 <= -dx
  vshufps     xmm3, xmm3, 0 ; xmm3[3:0] <= xmm3
  vinsertf128 ymm3, ymm3, xmm3, 1 ; ymm3[7:0] <= xmm3[3:0]
  vmulps      ymm15,ymm3, [packed_8] ; ymm15[7:0] *= 8 <= dx_mask
  
  xor   ecx,  ecx
  
; this loop is used for generating the "masks" which are used when the new
; arguments for the function need to be calculated. after this loop is finished
; working, ymm14 gets the "minus mask", which is ( -dx, 0, 2dx, 3dx, ... ), and
; ymm13 gets the "plus mask", which is ( dx, 2dx, 3dx, 4dx, ... ). both these
; masks, when added to the current position in the function, yield the arguments
; for the quadratic function used to calculate the value of its derivative.
; unfortunately, this is done via a temporary buffer on the stack.
align 16
.mask_loop:
  vmovss  [rsp+rcx],    xmm1
  vmovss  [rsp+rcx+32], xmm2
  vaddss  xmm1,         xmm0
  vaddss  xmm2,         xmm0
  add     ecx,          4
  cmp     ecx,          32
  jb      .mask_loop
  
  vmovaps ymm14,  [rsp] ; ymm14[7:0] <= minus_mask
  vmovaps ymm13,  [rsp+32] ; ymm13[7:0] <= plus_mask
  
  ; now the function arguments are moved to the ymm registers. thanks to the
  ; vbroadcast instruction, we don't need to bother with all of it ourselves.
  vaddss        xmm0, xmm0 ; xmm0 <= 2dx
  vshufps       xmm0, xmm0, 0 ; xmm0[3:0] <= 2dx
  vinsertf128   ymm0, ymm0, xmm0, 1 ; ymm0[7:0] <= xmm0[3:0]
  vbroadcastss  ymm1, [rdi] ; ymm1[7:0] <= start
  vbroadcastss  ymm2, [rdi+12] ; ymm2[7:0] <= a
  vbroadcastss  ymm3, [rdi+16] ; ymm3[7:0] <= b
  vbroadcastss  ymm4, [rdi+20] ; ymm4[7:0] <= c
  vmovaps       ymm5, ymm1 ; ymm5 holds the current position "in the function".
  
  mov eax,  [rdi+8] ; eax <= N
  mov rdx,  [rdi+24] ; rdx <= *dest
  xor ecx,  ecx
  shr eax,  3 ; eax /= 8 (8 elements processed in one iteration)

align 16
.diff_avx_loop:
  vaddps  ymm6, ymm5, ymm13 ; get new arguments (add the "plus mask")
  vmulps  ymm7, ymm6, ymm3 ; ymm7 <= b*x
  vmulps  ymm6, ymm6 ; ymm6 <= x^2
  vmulps  ymm6, ymm2 ; ymm6 <= a*(x^2)
  vaddps  ymm6, ymm7 ; ymm6 <= a*(x^2) + b*x
  vaddps  ymm6, ymm4 ; ymm6 <= a*(x^2) + b*x + c
  
  vaddps  ymm7, ymm5, ymm14 ; get new arguments (add the "minus mask")
  ; this is totally analogous to what's going on in the sequence above.
  vmulps  ymm8, ymm7, ymm3
  vmulps  ymm7, ymm7
  vmulps  ymm7, ymm2
  vaddps  ymm7, ymm8
  vaddps  ymm7, ymm4
  
  vsubps  ymm6, ymm7 ; f(x+dx) - f(x-dx)
  vdivps  ymm6, ymm0 ; (f(x+dx) - f(x-dx))/2dx
  vaddps  ymm5, ymm15 ; add the "dx mask" to every current argument
  
  vmovups [rdx],ymm6
  
  add rdx,  32
  add ecx,  1
  cmp ecx,  eax
  jb  .diff_avx_loop
  
  mov eax,  [rdi+8] ; eax <= N
  and eax,  7
  jz  .fun_end
  
  xor     ecx,    ecx
  vmovss  xmm11,  xmm0 ; xmm11 <= 2dx

align 16
.diff_single_loop:
; analogous to the "avx loop", but operating on a single argument in one
; iteration. this shouldn't really be an issue, since this loop will make at
; most 7 iterations.
  vaddss  xmm0, xmm5, xmm12 ; x+dx
  vsubss  xmm1, xmm5, xmm12 ; x-dx
  
  ; f(x+dx)
  vmulss  xmm6, xmm0, xmm3 ; b*x
  vmulss  xmm0, xmm0 ; x^2
  vmulss  xmm0, xmm2 ; a*(x^2)
  vaddss  xmm0, xmm6 ; a*(x^2)+b*x
  vaddss  xmm0, xmm4 ; a*(x^2)+b*x+c
  
  ; f(x-dx)
  vmulss  xmm6, xmm1, xmm3
  vmulss  xmm1, xmm1
  vmulss  xmm1, xmm2
  vaddss  xmm1, xmm6
  vaddss  xmm1, xmm4
  
  vsubss  xmm0, xmm1 ; f(x+dx) - f(x-dx)
  vdivss  xmm0, xmm11 ; /2dx
  vmovss  [rdx],xmm0
  
  vaddss  xmm5, xmm11 ; pos += dx
  add     rdx,  4
  add     ecx,  1
  cmp     ecx,  eax
  jb      .diff_single_loop

align 16
.fun_end:
  mov   rsp,  rbp
  pop   rbp
  ret
