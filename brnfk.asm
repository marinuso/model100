; ALTLCD Brainfuck for the TRS-100

; Features:
;   - Fully contained in ALTLCD, ergo no compatibility issues. Will not interfere with other TRS-100 software.
;   - Reads Brainfuck program from normal .DO file
;   - Has memory protection so that Brainfuck program cannot clobber the rest of RAM
;   - Uses all free RAM for the tape, giving you the biggest possible tape
;   - Programs can be halted by pressing F8 (or indeed other function key)
;   - Signal end-of-input by pressing Ctrl-Z.
;   - 0-on-EOF. 


; Undocumented 8085 instructions
LHLX		equ	0edh	; LHLX: HL = [DE]
SHLX		equ	0d9h	; SHLX: [DE] = HL 

; ROM functions
print_hl_on_lcd	equ	39d4h	; write HL to the screen in decimal 
print_string	equ	5a58h	; print the null-terminated string at HL
inlin		equ	463eh	; read line from keyboard and place at kbuf
wait_space	equ	5f2fh	; wait for spacebar to be pressed 
wait_key	equ	12cbh	; wait for a key to be pressed 
srcnam		equ	20afh	; find file whose name is in FILNAM 
memset		equ	4f0bh	; starting at HL, set B bytes of memory to A
strcpy		equ	65c3h	; copy from HL to DC until a NULL is found. 
memcpy		equ	6bdbh	; copy BC bytes from HL to DC 
buf_ch_upper	equ	0fe8h	; get character in M, make it uppercase, and store in A
newline		equ	4222h	; output CR+LF
shiftbreak	equ	729fh	; set Z and C flags if Shift+Break held


; RAM locations
altlcd		equ	0fcc0h	; alternate LCD buffer (320 bytes free for use)
combuf		equ	0ff46h	; serial buffer (64 bytes free for use)
kbuf		equ	0f685h	; line input buffer 
strend		equ	0fbb6h	; pointer to start of free RAM memory (we could store the "tape" there)
filnam		equ	0fc93h	; address where FILNAM 
timer		equ	0f92fh	; timer 

jmptbl		equ	0f700h  ; "jump table" start (in the key buffer)

; Variables
prog_start	equ	combuf   ; Pointer to start of program
tape_end	equ	combuf+2 ; Pointer to tape end  (start is at strend)
more_input	equ	tape_end+2 ; Set if more input available 



		org	altlcd	; The main program is run from ALTLCD
		
start		; Set the "more input" flag
		mvi	a,1
		sta	more_input
		
		; We'll reserve 64 bytes for the stack
		; The rest of the memory is used for the tape
		lxi	h,-64
		dad	sp
		shld	tape_end
		
		; Zero out the tape.
zero_tape	xchg		; Set DE = tape end location
		lhld	strend	; Set HL = tape start location
		; Zero out the tape from HL+1 to DE.
zero_loop	inx	h
		mvi	m,0
		rst	3
		jnz	zero_loop
				
ask_file	; Ask for filename
		call 	inlin
		rc	; if C flag set, Ctrl-C, so stop
		
		; Blank out the filename buffer
		lxi	h,filnam
		mvi	a,32
		mvi	b,6
		call	memset
		; Write default extension DO
		mvi	m,'D'
		inx	h
		mvi	m,'O'

parse_fname	; Parse the filename. Ignore the extension and assume it's .DO
		lxi	b,72eh	; C='.', B=Max file name length+1
		lxi	d,filnam
		lxi	h,kbuf
		
		; Get name of file
		call	parse_fn_part


parse_done	; FILNAM now contains the filename in the proper format
		call	srcnam		; Find the directory entry
		jz	ask_file	; Zero flag = No such file.
		; Check that the file type is right. Must be a DO file which is not killed.
		mvi	b,11000000b
		ana	b
		cmp	b
		jnz	ask_file
		; We found the file, the program start pointer is at DE.
		xchg
		shld	prog_start	; Store the program start pointer. 
				
		; We no longer need kbuf for anything, so we can now use it to make a jump table.
		; The characters needed are: < > + - . , [ ] and EOF (Ctrl-Z).
		; luckily, the whole command table fits in 256 bytes, so we can store the lower
		; byte of the address for each command in the corresponding byte in the table
		; The table starts at F700, which is within kbuf; it is 128 bytes long
		; (F700-F77F) such that the location for a character is H=F7 L=char.
		; The actual routine is then located at H=FD L=<table entry> 

set_up_jmptbl	; first, set the whole table to the invalid command routine (which is just RET)
		lxi	h,jmptbl
		mvi	b,128    	; 128 bytes
		mvi	a,cmd_invalid & 0ffh	; invalid command
		call	memset
		
		;lxi	h,jmptbl+26
		mvi	l,26		; EOF  = 26
		mvi	m,cmd_eof & 0ffh 
		mvi	l,'+'		 ; +   = 43 
		mvi	m,cmd_incr & 0ffh 
		inx	h		 ; ,   = 44 = 43 + 1
		mvi	m,cmd_in & 0ffh 
		inx	h		 ; -   = 45 = 44 + 1
		mvi	m,cmd_decr & 0ffh 
		inx	h		 ; .   = 46 = 45 + 1
		mvi	m,cmd_out & 0ffh
		mvi	l,'<'		 ; <   = 60
		mvi	m,cmd_left & 0ffh 
		inx	h		 ; >   = 62 = 60 + 2
		inx	h
		mvi	m,cmd_right & 0ffh
		mvi	l,'['		 ; [   = 91
		mvi	m,cmd_loop_start & 0ffh 
		inx	h		 ; ]   = 93 = 91 + 2
		inx	h
		mvi	m,cmd_loop_end & 0ffh
		
program_start	; Initialize the pointers
		lhld	prog_start
		mov	b,h
		mov	c,l
		lhld	strend
		inx	h
		xchg
		dcx	b
cmd_return	inx	b 
do_cmd		call	shbrk_timer	; make sure Shift+Break is occasionally checked 
		lxi	h,cmd_return	; store return address on stack
		push	h
		ldax	b		; get char under program pointer
		ana	a
		rm			; if sign bit set, invalid (this cuts table size in two)
		mvi	h,0f7h		; high byte for table entry = F7
		mov	l,a		; low byte for table entry = character code
		mov	l,m		; low byte for routine address = table entry 
	        mvi	h,0fdh		; high byte for routine address = FD
		pchl
		
;;;; Command routines 

;; Convention: on entry and exit, BC = program pointer; DE = tape pointer. 
;; On entry, A = command 
cmd_incr	xchg
		inr	m
		xchg
cmd_invalid	ret 
		
cmd_decr	xchg
		dcr	m
		xchg
		ret 
		
cmd_left	dcx	d
		lhld	strend	; check if end reached 
		rst	3
		mvi	a,0f4h  ; |- symbol 
		rnz
		jmp	error
		
cmd_right	inx	d
		lhld	tape_end ; check if other end reached
		rst	3
		mvi	a,0f9h  ; -| symbol 
		rnz		
error		rst	4
cmd_eof 	call	wait_space
		rst	0
	 
		
cmd_in		lxi	h,more_input ; check if EOF reached
		xra	a
		ora	m
		jz	in_to_tape ; yes = just write the 0 to the tape
		call	wait_key ; get character
		cpi	32
		jnc	echo_to_tape ; normal character
		cpi	3
		jz	0	; Ctrl+C or Shift-Break
		cpi	26	; end-of-input
		jz	in_eof
		cpi	13	; enter = \r from kbd, \r\n on screen and \n on tape
		jnz	echo_to_tape
		rst	4
		mvi	a,10
echo_to_tape	rst	4
in_to_tape	stax	d
		ret
in_eof		xra	a
		mov	m,a
		stax	d
		ret

		
cmd_out		ldax	d
		cpi	10	; if brainfuck outputs '\n', send '\r\n' instead
		jz	newline
		rst	4
		ret
		
cmd_loop_start	ldax	d	; check if memory zero 
		ana	a
		rnz
		mvi	a,23h	; 'inx h': seek forward
		push	de
		mvi	d,93h	; 'sub e': loop counter adjustment 
		jmp	cmd_loop 

cmd_loop_end	ldax	d	; check if memory nonzero
		ana	a 
		rz
		mvi	a,2bh	; 'dcx h': seek backwards 
		push	de
		mvi	d,83h	; 'add e': loop counter adjustment
		
cmd_loop	; adjust the loop commands
		sta	loop_next_char
		mov	a,d
		sta	adjust_counter
		
		; move BC (program pointer) to HL
		mov	h,b
		mov	l,c
		
		; C = loop counter
		mvi	c,1
		
		; move to next character
loop_next_char	inx	h	; NOTE: this is rewritten 
		call	shbrk_timer ; check for Shift-Break during loop
		
		; is this character [ ]? 
		mov	a,m
		cpi	'['
		jz	loop_char
		cpi	']'
		jnz	loop_next_char 
		
		; it is [ ] 
loop_char	sui	92 ; A is now -1 if [, 1 if ]
		mov	e,a
		mov	a,c
adjust_counter	add	e	; NOTE: this is rewritten 
		mov	c,a 
		
		
		; if d=0, we're done
		jnz	loop_next_char 
		; done: restore DE and copy the new prog.counter (in HL) to BC
		pop	de
		mov	b,h
		mov	c,l
		ret 
		

;;;; Subroutines 

;; Has a chance to stop the program if Shift+Break pressed. 
shbrk_timer	lda	timer
		ani	0fh
		cz	shiftbreak
		rnz
		rst	0

;; Read a maximum of B-1 bytes from [HL], making them uppercase and copying them into [DE],
;; incrementing HL and DE and decrementing B. 
;; Stop and return on C or 0. Pop stack and jump to ask_file if B reached.
parse_fn_part	call	buf_ch_upper	; A = uppercase [HL]
		; Check character
		cmp	c		; Is end character?
		rz			; Then return
		ana	a		; Is end of string?
		rz			; Then return
		; Write character and increment buffers
		xchg
		mov	m,a
		xchg
		inx	d
		inx	h
		dcr	b		; Exceeded chars yet?
		jnz	parse_fn_part	; No, so get another
		; We have too many characters
		; Remove the return address and go back to ask_file
		pop	hl
		jmp	ask_file
