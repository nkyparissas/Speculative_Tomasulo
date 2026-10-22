; Independent instructions alternate between the two execution units, so both
; functional units compete for the common data bus in the same cycles and the
; round-robin arbiter has to serialise their results.

OR   r11, r1, r2       ; 1 | 2 = 3
ADD  r12, r1, r2       ; 1 + 2 = 3
AND  r13, r3, r7       ; 3 & 7 = 3
SUB  r14, r10, r3      ; 10 - 3 = 7
NOT  r15, r6           ; ~6 = 0xFFFFFFF9
SLL  r16, r9           ; 9 << 1 = 18
OR   r17, r4, r8       ; 4 | 8 = 12
ADD  r18, r5, r5       ; 5 + 5 = 10
HALT
