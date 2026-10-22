; Eight independent additions exceed both the three arithmetic reservation
; stations and the three-stage arithmetic pipeline, so issue must stall until
; stations are released.

ADD  r11, r1, r1       ; 2
ADD  r12, r2, r2       ; 4
ADD  r13, r3, r3       ; 6
ADD  r14, r4, r4       ; 8
ADD  r15, r5, r5       ; 10
ADD  r16, r6, r6       ; 12
ADD  r17, r7, r7       ; 14
ADD  r18, r8, r8       ; 16
HALT
