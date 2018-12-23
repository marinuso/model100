; TRS-100 Invaders

; some subroutines from ROM
putch	equ	20h	; putchar w/o background taks handling 
bzero	equ	4f0ah	; zero out memory in HL
memcpy	equ	5a62h	; copy A bytes from DE to HL 
inkey	equ	7242h	; retrieve keypress, if there is one
plot	equ	744ch	; plot D=x E=y
unplot	equ	744dh	; unplot D=x E=y
restore	equ	14eeh	; pop BC, DE, HL, and return
drvwait	equ	7548h	; wait for the LCD driver
numout	equ	39d4h	; output number in HL
putstr	equ	5a58h	; print string
music	equ	72c5h	; DE=tone, B=duration

indcall	equ	6deh	; there's a PCHL in memory there, so calling here gives an indirect subroutine call

spaces	equ	5b2dh	; there's a zero-terminated string of nine spaces here

; some control constants
lcdsz	equ	50	; LCD driver width
sprtsz	equ	9	; sprite width
mem	equ	0ff47h	; here we keep our working memory (64 bytes of serial buffer free to use, but offset 1 into it) 

; control variables
currow	equ	0f639h
curcol	equ	0f63ah
keyrep	equ	0ffa4h	; this controls how fast the keys repeat

; game constants
strtpos	equ	71	; player starts at x=71 at the start of the game
maxpos	equ	141	; player maximum position
bullpos	equ	53	; player's bullet starts at y=53 when shot
bullspd	equ	8	; bullet speed divider

alispd	equ	12	; game speed divider
alicols equ	8	; amount of columns
alispos	equ	18	; aliens start X position

s_empty	equ	3b6h	; there's a line of zeroes in ROM here that can be used

; working memory variables

counter	equ	mem-1	; counter - doesn't need to be initialized - used to determine which alien should shoot 

; note: the order of these matters, they are loaded into DE at once

yaliblt	equ	mem	; alien bullet, Y position (or 0 if no bullet)
xaliblt	equ	mem+1	; alien bullet, X position

;score	equ	mem+2	; 2-byte score variable

yplblt	equ	mem+4	; player bullet, Y position (or 0 if no bullet)
xplblt	equ	mem+5	; player bullet, X position

;xplayer	equ	mem+6	; player X position   

; mvmt of aliens
;alidir	equ	mem+7 ; 1=rightwards, -1=leftwards
aliwait equ	mem+7 ; alien slowdown counter
alienx	equ	mem+8 ; aliens X draw position

; columns of aliens
aliens0 equ	mem+9
aliens1 equ	mem+10
aliens2 equ	mem+11
aliens3 equ	mem+12
aliens4 equ	mem+13
aliens5 equ	mem+14
aliens6	equ	mem+15
aliens7	equ	mem+16

alidir	equ	mem+17

;; vars that don't need initialization ;;
hixpos	equ	mem+18 ; highest X position for an alien that was drawn last screen
lowxpos	equ	mem+19 ; lowest X position for an alien that was drawn last screen

	org	0fcc0h	

inigame	; initialize all the variables from the initialization block at the end
	mvi	a,inilen
	lxi	de,varini
	lxi	hl,mem
	call	memcpy

; clear the screen
; (needed when new level or aliens have moved down)
clrscrn	mvi	e,7
clcol	mvi	d,144
clpos	lxi	hl,s_empty
;	push	de
	call	sprite
;	pop	de
	mov	a,d
	sui	9
	mov	d,a
;	dcr	d
	jnc	clpos
	dcr	e
	jp	clcol

screen	; push the "screen" return address on the stack (it will be jumped back to)
	lxi	hl,screen
	push	hl

	; update the screen
	
	; draw the score
	;set cursor position at score counter
	lxi	hl,2008h
;	push	hl
	shld	currow
;	lxi	hl,spaces+4
;	call	putstr
;	pop	hl
	lhld	score
	call	numout

	; draw the player and correct movement
splayr	lxi	hl,xplayer
	mov	a,m
	cpi	maxpos+1
	jz	setmax
	cpi	255
	jnz	drawpl
	mvi	m,0
	jmp	drawpl

;;;"DEAD ZONE";;; store vars here

; sprites

s_alien	db	0,141, 94, 50, 30, 50, 94,141 ; last 0 overlaps with player
s_alie2	db	0,109,158,178, 30,178,158,109 
s_playr db	0,192,240,240,248,240,240,192 ; last 0 overlaps with varini 

; initial variable settings
varini 
	db	0,0 ; yaliblt,  xaliblt
score	db	0,0 ; score
	db	0,0 ; yplblt, xplblt
xplayer	db	strtpos ; playerx
	db	alispd, alispos ; aliwait, alienx
	db	62,62,62,62 ; aliens0 aliens1 aliens2 aliens3 
	db	62,62,62,62 ; aliens4 aliens5 aliens6 aliens7
	db	1 ; alidir

inilen  equ	$-varini

;;;


setmax	mvi	m,maxpos
drawpl	mov	d,m
	mvi	e,7
	lxi	hl,s_playr
	call	sprite

	;regulate game speed
;	lxi	hl,bltwait
;	dcr	m
;	jnz	keybd
;	mvi	m,bullspd


	;draw the player's bullet if he has one
splblt	lda	yplblt
	ora	a
	jz	saliens	; no bullet
	
	;bullet: undraw the stored bullet
	mvi	e,unplot & 0ffh
	call	pblthdl

	;move the bullet upwards
	lxi	hl,yplblt
	dcr	m
	jz	saliens ; and don't redraw it if it reached the top

bredraw ;draw the bullet in its new position
	mvi	e,plot & 0ffh
	call	pblthdl

	
saliens ;draw the aliens

	; set lowxpos to 0 (hixpos is updated through every loop anyway)
	xra	a
	sta	lowxpos
	; set B to 0 too - B will be or'ed with every column of aliens
	mov	b,a

	; C stores how many columns left
	mvi	c,alicols
	; D starts at the column start position
	lxi	hl,alienx
	mov	d,m
	
sacol	; increment pointer to point at the right start position
	inx	hl
	;draw a column of aliens - HL is pointing at the column (in m), D has the X coord
	mvi	e,7	; alien row
	
	;any aliens at all left in this column?
	xra	a
	ora	m
	jz	colmty

	;yes - or B with them
	ora	b
	mov	b,a

	;both the bullet check routine and the position update use hl
	push	hl

	;hixpos must always be updated, since we are drawing here and it's done in order
	;at this point HL points to an alien row, which is in h=FF just like hixpos
	mvi	l,hixpos	;lxi	hl,hixpos
	mov	m,d
	;lowpos must only be update if it is not set yet
	inx	hl
	xra	a
	ora	m
	jnz	noxset
	mov	m,d	

	;update sprite pointer
	lxi	hl,s_alien
	mov	a,d
	ani	1
	rlc
	rlc
	rlc
	add	l
	;lxi	hl,drwhl+1
	;mov	m,a
	mov	l,a
	shld	drwhl+1

	
	;set it to  ignore the bullet check routine
noxset	lxi	hl,drwali	
	shld	buljmp+1			

	;;; drwali and noajmp both have h=FDh so we only need to set l here 
	mvi	l,noajmp	;lxi	hl,noajmp
	push	hl

	;check if the player bullet is in this position
	lda	yplblt
	ana	a
	rz	;noajmp
	lda	xplblt
	dcr	a	
	cmp	d
	rc	;noajmp
	sui	7
	cmp	d
	rnc	;noajmp
	pop	hl

	;yes, so set it to run the bullet check routine
	;;; bulchk is in FDh too so again only L is needed
	mvi	l,bulchk	;lxi	hl,bulchk
	shld	buljmp+1	
noajmp	pop	hl
	mov	a,m
chkali  ;alien at this position?
	rar
	jnc	noali

buljmp	jmp	drwali	;this is overwritten with bulchk iff the bullet is in the right column and active

	; see if there is a bullet here too
bulchk	lda	yplblt
	;divide a by 8 and see if it is equal to E (= row is OK)
	ani	0f8h
	rrc
	rrc
	rrc
	cmp	e
	jnz	drwali	;bullet not in right row

	;we got here, so we have a bullet right here
	;so unset the alien in the column variable so we don't redraw it
	mvi	a,0feh
	ana	m
	mov	m,a

	;undraw and unset the bullet
	push	hl
	push	bc
	push	de

	lxi	de,unplot
	call	pblthdl
	xra	a
	sta	yplblt

	;unset the bullet check routine too so we don't react to the same bullet twice
	lxi	hl,drwali
	shld	buljmp+1


	;increase the score
	lxi	de,score
	db	0edh ;LHLDE
	inx	hl
	db	0d9h ;SHLDE

	;lhld	score
	;inx	hl
	;shld	score

	pop	de
	pop	bc

	;and set the draw routine to draw an empty sprite instead
	lxi	hl,s_empty
	shld	drwhl+1

	pop	hl
	
	;yes, draw him
drwali	push	hl
	push	bc
;	push	de
drwhl	lxi	hl,s_alien ; note: rest of the code may overwrite this
	call	sprite
	;restore registers
;	pop	de
	pop	bc
	; not hl yet - the shooting routine uses it

	;the alien shoots if there is no alien bullet already and the timer says so
	;(if he gets hit at that exact time, he'll still get a shot off)
alisht	lxi	hl,counter
	dcr	m
	jnz	noshoot
	xra	a
	;lxi	hl,yaliblt
	inx	hl
	ora	m
	jnz	noshoot ; there is already a bullet on the screen
	
	;we will shoot - in E is the alien row. yaliblt=(E+1)*8
	mov	a,e
	inr	a
	rlc
	rlc
	rlc
	mov	m,a

	;the alien should shoot from its middle
	;in D is the alien column - xaliblt=D+4
	inx	hl
	mov	a,d
	adi	4
	mov	m,a 
	

noshoot	pop	hl
noali	;rotate through to next alien
	mov	a,m
	rlc
	mov	m,a
	
	;adjust row
	dcr	e
	jp	chkali

	;draw the next column 11 pxls onward
colmty	mov	a,d
	adi	15
	mov	d,a
	;decrease column count
	dcr	c
	;if any left, draw next column
	jnz	sacol

	;check if there are any aliens left at all and reinitialize if not
	xra	a
	ora	b
	;there's still a return address on the stack so make sure it gets popped off
	lxi	hl,inigame
	xthl
	rz	;inigame
	xthl

	;draw the alien bullet last, if there is one
	
	;check if the alien bullet hits the player
	lhld	yaliblt  ;H=x L=y bullet
	; 0=Y = no bullet
	xra	a
	cmp	l
	jz	noablt
	; 56>Y = bullet is above the player 
	mvi	a,58
	cmp	l
	jnc	nohit
	lda	xplayer	;A = x player
	; Xplayer > X = bullet to the left of player
	; inr A;
	;inr	a
	dcr	a
	cmp	h
	jnc	nohit
	; Xplayer+4 > X = bullet inside player, hit
	adi	9;7
	cmp	h
	jnc	plrdies 


nohit	; undraw last bullet
	mvi	e,unplot & 0ffh
	call	ablthdl
	
	; advance bullet
	lxi	hl,yaliblt
	inr	m	
	push	hl

	; draw the bullet in the new position
	mvi	e,plot & 0ffh
	call	ablthdl

	; zero it out if it's too low
	pop	hl
	mvi	a,60
	cmp	m
	jnz	noablt
	mvi	m,0

	;inr	e
	;call	ablthdl
	
	;wait the required bunch of frames before actually moving the aliens
noablt	lxi	hl,aliwait
	dcr	m
	jnz	keybd
	mvi	m,alispd
	

	;if the lowest position was 1, or the highest position was >140, we must turn around
	lxi	hl,lowxpos
	dcr	m
	dcx	hl	
	
	jz	doturn
	mvi	a,140
	cmp	m
	jnc	domove	; hipos is ok too
	
	; we have to turn
doturn	dcx	hl	; alidir is just below hixpos in memory lxi	hl,alidir
	mov	a,m
	cma
	inr	a
	mov	m,a


	; the aliens also need to be lowered
	mvi	l,aliens0 	;lxi	hl,aliens0
	mvi	c,alicols
lwrali	mov	a,m
	rlc
	mov	m,a
;	; if an alien has reached the 8th row, game over
	rar
	jc	plrdies

	inx	hl
	dcr	c
	jnz	lwrali
	
	; and we'll need to return to 'clrscrn' instead of 'screen' next loop	
	lxi	hl,clrscrn
	xthl

domove	
	lxi	hl,alienx
	lda	alidir
	add	m
	mov	m,a
	
keybd	
	call	inkey
	
	jc	0 ; back to the menu on special keys (this includes F8 so we're good)

	; make sure the keys repeat fast
	; H is already guaranteed to be FF (all working memory is there) so we can save a byte by only setting L
	mvi	l,keyrep	;lxi	hl,keyrep
	mvi	m,1
	
	; set hl to be the player position
	; H is still FF of course
	;mvi	l,xplayer	;lxi	hl,xplayer
	lxi	hl,xplayer

	; check keys
	cpi	'j'
	jz	left
	cpi	'k'
	jz	right
	cpi	' '
	rnz	; return if _not_ a space - if space, fall through into shoot
	;jz	shoot

	; something else? never mind

	;ret	; the "screen" address is on the stack still

; handle keys - hl is already the player

shoot	; already have bullet? then do nothing, one bullet at a time
	lda	yplblt
	ora	a
	rnz	
	; otherwise, shoot the bullet
	;mvi	a,bullpos
	;sta	yplblt<F8>
	;mov	a,m ; this is player's X
	;adi	4 ; middle of player
	;sta	xplblt
	
	mov	a,m	; player's X
	adi	4
	lxi	h,xplblt
	mov	m,a
	dcx	h
	mvi	m,bullpos

	ret

left	equ	38fah ; the code 'dcr m - ret' is already in ROM here so let's call it and save 2 bytes
	;dcr	m
	;ret
right	equ	3470h ; and 'inr m - ret' can be found in ROM too	
	;inr	m
	;ret

; player dies
plrdies	; pop the "screen" return address off the stack
	mvi	e,7
	lda	xplayer
	mov	d,a
	xthl
	call	sprite
	mvi	d,23h
	mvi	b,50
	call	music
	call	23908
	rst	0	

; either undraw or draw the alien's bullet (calling the function in DE)
ablthdl lhld	yaliblt
	jmp	blthdl
; either undraw or draw the player's bullet (calling the function in DE)
pblthdl	; load bullet into DE
	lhld	yplblt
blthdl	xchg
	mvi	b,2
	mvi	h,plot>>8 ; It's always PLOT or UNPLOT, so this saves one byte on each call
bltloop	call	enclose
	inr	e
	dcr	b
	jnz	bltloop
enclose	push	hl
	push	de
	push	bc
	lxi	bc,restore
	push	bc
	pchl 
	;call	indcall
	;jmp	restore
	
	
; draw 9x8 sprite on screen d=x (pos) e=y/8 hl=start
sprite  ; get lcd array info for (x,y) position in de
	; save de so it can be reused
	push	de
	mvi	b,1	; b holds driver bitptn
	
shget	mov	a,d	; get current bank
	sui	lcdsz	; is it that bank?	
	jm	svget	
	mov	d,a	; it isn't, store it back
	mov	a,b
	rlc
	mov	b,a
	jmp	shget
svget	mov	a,e	; adjust to point to the lower driver if necessray
	ani	252	; if e>4 then we need lower driver
	jz	sdrvr
	mov	a,b	; we need 5 drivers onwards
	rlc
	rlc
	rlc
	rlc
	rlc
	mov	b,a
sdrvr	; b = driver switch, d = driver X coord, e = driver Y coord
	; join driver Y and X coords into driver positio nin e
	mov	a,e;
	ani	3
	rlc
	rlc
	rlc
	rlc
	rlc
	rlc
	ora	d
	mov	e,a
	; b = driver switch, d = driver X coord, e = LCD driver pos
	; we might need to switch driver halfway through if d>40.
	; switching to the next driver is fortunately as easy as rlc on b
	mvi	a,lcdsz
	sub	d
	mov	d,a
	; D = how many positions left in current driver
	mvi	c,sprtsz ; how many positions left in pos
	di	; we don't want to be interrupted
	in	0bah
	ani	252
	out	0bah
	mov	a,b
sdrvsel	out	0b9h
	;initial position set
	mov	a,e
	out	0feh	
	call	drvwait
sbyte	; push byte out
	mov	a,m
	out	0ffh
	inx	hl	; next byte
	dcr	c	; done yet?
	jz	sdone	; yup!
	dcr	d	; need next driver?
	jnz	sbyte   ; no, next byte
sdrvadj ; yes, we do: set X coord to 0 for next drv
;	mvi	d,lcdsz
	mov	a,e
	ani	192	; zero out everything but the bank position
	mov	e,a
	mov	a,b
	rlc
	jmp	sdrvsel
sdone	pop	de
	ei	; turn interrupts back on
	ret
	

