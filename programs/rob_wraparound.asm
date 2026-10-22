; Twenty instructions with mixed dependencies, so that the 15-entry reorder
; buffer wraps around while operands are still being looked up in it.

ADD  r11, r1, r2       ; 3
ADD  r12, r3, r4       ; 7
OR   r13, r11, r12     ; 3 | 7 = 7
AND  r14, r12, r5      ; 7 & 5 = 5
SUB  r15, r13, r14     ; 7 - 5 = 2
SLL  r16, r15          ; 4
NOT  r17, r16          ; ~4 = 0xFFFFFFFB
ADD  r18, r16, r16     ; 8
OR   r19, r18, r1      ; 8 | 1 = 9
SUB  r20, r19, r2      ; 9 - 2 = 7
AND  r21, r20, r19     ; 7 & 9 = 1
ADD  r22, r21, r10     ; 11
SLL  r23, r22          ; 22
OR   r24, r23, r3      ; 22 | 3 = 23
SUB  r25, r24, r22     ; 23 - 11 = 12
ADD  r26, r25, r25     ; 24
NOT  r27, r26          ; ~24 = 0xFFFFFFE7
AND  r28, r27, r24     ; 0xFFFFFFE7 & 23 = 7
OR   r29, r28, r9      ; 7 | 9 = 15
ADD  r30, r29, r30     ; 15 + 0 = 15
HALT
