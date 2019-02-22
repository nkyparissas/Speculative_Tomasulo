# Hardware-based Speculation (Speculative Tomasulo)
An Out-of-Order Processor in VHDL based on the Speculative Tomasulo algorithm.  
Computer Architecture coursework, Technical University of Crete, School of ECE.

For this project, only behavioral simulation was requested from us, so the code hasn't been tested beyond that. The code is synthesizable except for INSTRUCTION_FETCH, which uses non-synthesizable functions to handle the "rom.data" file as a ROM. By replacing those functions with an initialized BRAM containing the same instructions, the whole design can then be synthesized.

![](Speculative_Tomasulo.png) 
