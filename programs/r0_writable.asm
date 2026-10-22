; Register r0 is an ordinary register in this architecture rather than a
; hard-wired zero, so it can be written and read back.

ADD  r0, r5, r5        ; r0 = 10
OR   r11, r0, r1       ; r11 = 10 | 1 = 11
HALT
