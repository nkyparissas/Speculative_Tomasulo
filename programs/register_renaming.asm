; Write-after-write and write-after-read hazards on r11. The reorder buffer
; must supply each reader with the value of the most recent older writer.

ADD  r11, r1, r2       ; r11 = 3
OR   r12, r11, r0      ; r12 = 3, reads the first r11
ADD  r11, r3, r4       ; r11 = 7, WAW with the first ADD and WAR with the OR
AND  r13, r11, r5      ; r13 = 7 & 5 = 5, must read the second r11
SUB  r11, r11, r1      ; r11 = 6, reads and overwrites r11
OR   r14, r11, r12     ; r14 = 6 | 3 = 7
HALT
