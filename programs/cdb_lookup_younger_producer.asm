; The final OR issues in the cycle in which the CDB broadcasts the first write
; of r11, while a younger write of r11 is still in flight. The ROB lookup must
; report the younger producer instead of forwarding the broadcast value, as it
; did before KI-4 was fixed.

OR   r11, r0, r1       ; r11 = 1
ADD  r11, r11, r2      ; r11 = 3, waits for the first r11
AND  r13, r3, r7       ; r13 = 3 (independent)
OR   r14, r4, r5       ; r14 = 5 (independent)
SUB  r15, r9, r8       ; r15 = 1 (independent)
OR   r16, r11, r0      ; r16 = 3
HALT
