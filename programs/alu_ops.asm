; Executes every operation once on independent operands, so that each result
; depends only on the initial register values and not on forwarding.

OR   r11, r5, r10      ; 5 | 10 = 15
AND  r12, r7, r5       ; 7 & 5 = 5
NOT  r13, r9           ; ~9 = 0xFFFFFFF6
ADD  r14, r8, r9       ; 8 + 9 = 17
SUB  r15, r3, r4       ; 3 - 4 = 0xFFFFFFFF (wraps around)
SLL  r16, r10          ; 10 << 1 = 20
HALT
