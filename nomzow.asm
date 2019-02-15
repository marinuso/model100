;;; NOMZOW
;;; Small WozMon clone that fits in the keyboard buffer, leaving ALTLCD free to
;;; poke your own code into. 

;;; ROM addresses 
readline	equ	4644h	; read a line from the keyboard and put it in the buffer
buf_ch_upper	equ	0fe8h	; get the character HL is pointing to and make it uppercase
indirect	equ	06deh	; make an indirect subroutine call 
cls		equ	4231h	; clear the screen 
crlf		equ	4222h	; send a newline to the screen 
getch_upper	equ	5d64h	; read key from keyboard and convert to uppercase

;;; RAM addresses
kbd_input_buf	equ	0f685h
serial		equ	0ff46h

;;; memory
;;; we don't initialize these, of course 
select		equ	serial	; holds the last shown address 
write		equ	serial+2 ; holds the last typed or written to address
keybuf		equ	serial+4 ; store keys here 


;;; RDEL undocumented instruction
rdel		equ	18h


		org	kbd_input_buf  

		push	hl
get_line_pop	; for jumping to from a subroutine, canceling it
		pop 	hl 
		; read a line (of max. 39 chars) into the serial buffer 
get_line	; output newline character
		call	crlf
		; read into the serial buffer, max. 39 chars 
		lxi	hl,keybuf
		mvi	e,39
read_char	call	getch_upper
		cpi	13	;Enter key
		jz	line_done
		cpi	32	;Don't handle special keys, just restart input
		jc	get_line
		; echo the character 
		rst	4
		; it was a normal key,store it
		mov	m,a
		inx	hl
		; get next char if not full
		dcr	e
		jnz	read_char
		; full: restart 
		jmp	get_line
		
		; read a line 	
;get_line	call	readline

line_done	call	crlf
		mvi	m,0
		mvi	l,4ah 	;lxi	hl,serial 
		;lxi	hl,keybuf 
		;lxi	hl,kbd_input_buf
		
		; skip all whitespace
process		call	skip_whitespace
		
		;xra	a
		;ora	m
		;jz	get_line	; zero = end of line
		;cpi	33
		;jnc	do_cmd
		;inx	hl
		;jmp	process

do_cmd		;; if we have a hexadecimal value, read, set addresses, and show values
		call	hex_in_char
		jnc	addr_in

		;; if we have '.', only set the 2nd addr and show values
		mvi	a,'.'
		cmp	m
		jz	snd_addr_in
		
		;; if we have ':', start reading values and writing
		mvi	a,':'
		cmp 	m
		jz	write_bytes_in
		
		;; if we have 'R', jump to the write address
		mvi	a,'R'
		cmp	m
		jz	call_pgm
		
		;; command character wasn't recognized, so disregard the line and get a new one
		jmp	get_line

;;; call routine at write address ('xxxxR')
call_pgm	push	hl
		lhld	write
		call 	indirect
		pop	hl
		inx	hl
		jmp	process 
		
;;; rest of line should contain bytes to write
write_bytes_in	inx	hl			; skip over the ':'
write_bytes	call	skip_whitespace
		call	hex_or_line
		mov	b,e			; we only need to store e because we're writing bytes
		xchg
		lhld	write			; get the write address
		mov	m,b			; write the byte
		inx	hl			; increase the address
		shld	write
		xchg				; restore pointer to input 
		jmp	write_bytes		; go back for more 
		
		
;;; move hl forward until next non-whitespace character
;;; if reach end of line, get new line 

skip_whitespace xra	a
		ora	m
		jz	get_line_pop
		cpi	33
		rnc
		inx	hl
		jmp	skip_whitespace

;;; set the select and write address, and output 
addr_in		;read the first hex value, and store it in both the select
		;and write addresses
		call	hex_in_val
		xchg
		shld	select
		shld	write
		call	addr_hl_out	
		xchg 
		
		jmp	show_mem
		

		;2nd entry point to read only end addr 
snd_addr_in	inx	hl
		call	hex_or_line
		
show_mem	;the last read hex value is now in DE (whether there were one or two)
		;from <select> to DE should be written to the screen
		push	hl
		lhld	select
		
byte_out	;write the current byte on the screen
		mov	b,m
		call	hex_out_b
		mvi	a,' '
		rst	4
		
		;are we done yet? (i.e., hl == de ; hl >= de )
		mov	a,h
		cmp	d
		jc	next_byte ;show_done ; d<h 
		mov	a,l
		cmp	e 
		jnc	show_done  ;!(l<e)
		
next_byte	inx	hl	
		mov	a,l ; if this is the 8th byte, show the address again 
		ani	7
		cz	addr_hl_out
		jmp	byte_out ; otherwise show the next byte 

show_done	;the last shown address is now the selected address
		;BUT NOT the write address
		inx 	hl
		shld	select
		pop	hl	; restore pointer to keyboard buffer
		jmp	process 

;;; routine: write the address 'hl' on the screen with proper format
addr_hl_out	call	crlf
		call 	hex_out_hl
		mvi	a,':'
		rst	4
		mvi	a,' '
		rst	4
		ret
		
		
;;; get hex value if there is a valid hex value, jump to get_line otherwise 		
hex_or_line	call	hex_in_char
		jc	get_line_pop
		
;;; read hexadecimal characters until the next character is not hexadecimal
;;; output: DE hexadecimal value, HL points to next non-hex character
hex_in_val	lxi	de,0		; DE starts at 0 
get_char 	call	hex_in_char	
		rc			; not a valid hexadecimal character
	        db	rdel,rdel,rdel,rdel ; make room for the nybble
		ora	e
		mov	e,a 		; store it
		inx	hl		; next character
		jmp	get_char 
		
;; get hexadecimal character under the HL pointer
;; A will be set to the hex value. Carry flag will be set if invalid character. 
hex_in_char     mov	a,m
		sui	48		; subtract '0' to make it a number
		rc			; it's < 48, error
		cpi	10		; is it still > 9? 
		jc	hex_nyb		; no - we have the nybble value
		sui	7		; yes - correct for the distance between '9' and 'A'
		cpi	10		
		rc			; it's >'9' and <'A', error 
hex_nyb		cpi	16		; set the carry flag if nybble>16
		cmc
		ret
		
;;; hexadecimal output routine
hex_out_hl	mov	b,h		; output high byte 
		call	hex_out_b
		mov	b,l 		; fall through to output low byte 
hex_out_b	; output B as byte
		mov	a,b
		rrc			; move high nybble into low nybble
		rrc
		rrc
		rrc
		call	hex_out_a_l	; output
		mov	a,b		; fall through to output the low nybble 
hex_out_a_l	; output lower nybble of A 
		ani	00001111b 	; get lower nybble
		adi	48		; add '0'
		cpi	58		; is it a proper digit?
		jc	hex_out_char 	; then print it
		adi	7		; otherwise, add 7 to make it a correct letter
hex_out_char	rst	4		; and print it 
		ret		
		