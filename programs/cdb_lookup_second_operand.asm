; The final ADD issues in the cycle in which the CDB broadcasts the producer of
; its first source r11, while its second source r12 still waits for the first
; ADD. The ROB lookup must report the pending producer of r12 instead of
; falling back to the register file, as it did before KI-4 was fixed.

OR   r11, r0, r1       ; r11 = 1
ADD  r12, r11, r2      ; r12 = 3, waits for r11
AND  r13, r3, r7       ; r13 = 3 (independent)
OR   r14, r4, r5       ; r14 = 5 (independent)
SUB  r15, r9, r8       ; r15 = 1 (independent)
ADD  r16, r11, r12     ; r16 = 1 + 3 = 4
HALT
