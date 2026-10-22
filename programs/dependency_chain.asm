; A chain of read-after-write dependencies that alternates between the two
; execution units, so that every operand arrives through a CDB broadcast.

ADD  r11, r1, r2       ; 1 + 2 = 3
OR   r12, r11, r4      ; 3 | 4 = 7
SUB  r13, r12, r1      ; 7 - 1 = 6
AND  r14, r13, r10     ; 6 & 10 = 2
SLL  r15, r14          ; 2 << 1 = 4
NOT  r16, r15          ; ~4 = 0xFFFFFFFB
ADD  r17, r16, r5      ; 0xFFFFFFFB + 5 = 0 (wraps around)
HALT
