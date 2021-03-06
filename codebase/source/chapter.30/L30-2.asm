;
; *** Listing 8.2 ***
;
; Demonstrates the interaction of the split screen and
; horizontal pel panning. On a VGA, first pans right in the top
; half while the split screen jerks around, because split screen
; pel panning suppression is disabled, then enables split screen
; pel panning suppression and pans right in the top half while the
; split screen remains stable. On an EGA, the split screen jerks
; around in both cases, because the EGA doesn't support split
; screen pel panning suppression.
;
; The jerking in the split screen occurs because the split screen
; is being pel panned (panned by single pixels--intrabyte panning),
; but is not and cannot be byte panned (panned by single bytes--
; "extrabyte" panning) because the start address of the split screen
; is forever fixed at 0.
;
; Assembled with TASM 4.0, linked with TLINK 6.10
; Checked by Jim Mischel 11/21/94
;*********************************************************************
IS_VGA	equ	1		;set to 0 to assemble for EGA
;
VGA_SEGMENT	equ	0a000h
LOGICAL_SCREEN_WIDTH equ 1024	;# of pixels across virtual
				; screen that we'll pan across
SCREEN_HEIGHT	equ	350
SPLIT_SCREEN_START equ	200	;start scan line for split screen
SPLIT_SCREEN_HEIGHT equ	SCREEN_HEIGHT-SPLIT_SCREEN_START-1
CRTC_INDEX	equ	3d4h	;CRT Controller Index register
AC_INDEX		equ	3c0h	;Attribute Controller Index reg
OVERFLOW		equ	7	;index of Overflow reg in CRTC
MAXIMUM_SCAN_LINE equ	9	;index of Maximum Scan Line register
				; in CRTC
START_ADDRESS_HIGH equ	0ch	;index of Start Address High register
				; in CRTC
START_ADDRESS_LOW equ	0dh	;index of Start Address Low register
				; in CRTC
HOFFSET		equ	13h	;index of Horizontal Offset register
				; in CRTC
LINE_COMPARE	equ	18h	;index of Line Compare reg (bits 7-0
				; of split screen start scan line)
				; in CRTC
AC_MODE_CONTROL	equ	10h	;index of Mode Control reg in AC
PEL_PANNING	equ	13h	;index of Pel Panning reg in AC
INPUT_STATUS_0	equ	3dah	;Input Status 0 register
WORD_OUTS_OK	equ	1	;set to 0 to assemble for
				; computers that can't handle
				; word outs to indexed VGA registers
;*********************************************************************
; Macro to output a word value to a port.
;
OUT_WORD	macro
if WORD_OUTS_OK
	out	dx,ax
else
	out	dx,al
	inc	dx
	xchg	ah,al
	out	dx,al
	dec	dx
	xchg	ah,al
endif
	endm
;*********************************************************************
MyStack	segment para stack 'STACK'
	db	512 dup (0)
MyStack	ends
;*********************************************************************
Data	segment
SplitScreenLine	dw	?	;line the split screen currently
				; starts after
StartAddress	dw	?	;display memory offset at which
				; scanning for video data starts
PelPan		db	?	;current intrabyte horizontal pel
				; panning setting
Data	ends
;*********************************************************************
Code	segment
	assume	cs:Code, ds:Data
;*********************************************************************
Start	proc	near
	mov	ax,Data
	mov	ds,ax
;
; Select mode 10h, 640x350 16-color graphics mode.
;
	mov	ax,0010h	;AH=0 is select mode function
				;AL=10h is mode to select,
				; 640x350 16-color graphics mode
	int	10h
;
; Set the Offset register to make the offset from the start of one
; scan line to the start of the next the desired number of pixels.
; This gives us a virtual screen wider than the actual screen to
; pan across.
; Note that the Offset register is programmed with the logical
; screen width in words, not bytes, hence the final division by 2.
;
	mov	dx,CRTC_INDEX
	mov	ax,(LOGICAL_SCREEN_WIDTH/8/2 shl 8) or HOFFSET
	OUT_WORD
;
; Set the start address to display the memory just past the split
; screen memory.
;
	mov	[StartAddress],SPLIT_SCREEN_HEIGHT*(LOGICAL_SCREEN_WIDTH/8)
	call	SetStartAddress
;
; Set the split screen start scan line.
;
	mov	[SplitScreenLine],SPLIT_SCREEN_START
	call	SetSplitScreenScanLine
;
; Fill the split screen portion of display memory (starting at
; offset 0) with a choppy diagonal pattern sloping left.
;
	mov	ax,VGA_SEGMENT
	mov	es,ax
	sub	di,di
	mov	dx,SPLIT_SCREEN_HEIGHT
				;fill all lines in the split screen
	mov	ax,0FF0h	;starting fill pattern
	cld
RowLoop:
	mov	cx,LOGICAL_SCREEN_WIDTH/8/4
				;fill 1 scan line
ColumnLoop:
	stosw			;draw part of a diagonal line
	mov	word ptr es:[di],0 ;make vertical blank spaces so
				; panning effects can be seen easily
	inc	di
	inc	di
	loop	ColumnLoop
	rol	ax,1		;shift pattern word
	dec	dx
	jnz	RowLoop
;
; Fill the portion of display memory that will be displayed in the
; normal screen (the non-split screen part of the display) with a
; choppy diagonal pattern sloping right.
;
	mov	di,SPLIT_SCREEN_HEIGHT*(LOGICAL_SCREEN_WIDTH/8)
	mov	dx,SCREEN_HEIGHT ;fill all lines
	mov	ax,0c510h	;starting fill pattern
	cld
RowLoop2:
	mov	cx,LOGICAL_SCREEN_WIDTH/8/4
				;fill 1 scan line
ColumnLoop2:
	stosw			;draw part of a diagonal line
	mov	word ptr es:[di],0 ;make vertical blank spaces so
				; panning effects can be seen easily
	inc	di
	inc	di
	loop	ColumnLoop2
	ror	ax,1		;shift pattern word
	dec	dx
	jnz	RowLoop2
;
; Pel pan the non-split screen portion of the display; because
; split screen pel panning suppression is not turned on, the split
; screen jerks back and forth as the pel panning setting cycles.
;
	mov	cx,200	;pan 200 pixels to the left
	call	PanRight
;
; Wait for a key press (don't echo character).
;
	mov	ah,8	;DOS console input without echo function
	int	21h
;
; Return to the original screen location, with pel panning turned off.
;
	mov	[StartAddress],SPLIT_SCREEN_HEIGHT*(LOGICAL_SCREEN_WIDTH/8)
	call	SetStartAddress
	mov	[PelPan],0
	call	SetPelPan
;
; Turn on split screen pel panning suppression, so the split screen
; won't be affected by pel panning. Not done on EGA because both
; readable registers and the split screen pel panning suppression bit
; aren't supported by EGAs.
;
if IS_VGA
	mov	dx,INPUT_STATUS_0
	in	al,dx		;reset the AC Index/Data toggle to
				; Index state
	mov	al,20h+AC_MODE_CONTROL
				;bit 5 set to 1 to keep video on
	mov	dx,AC_INDEX	;point to AC Index/Data register
	out	dx,al
	inc	dx		;point to AC Data reg (for reads only)
	in	al,dx		;get the current AC Mode Control reg
	or	al,20h		;enable split screen pel panning
				; suppression
	dec	dx		;point to AC Index/Data reg (Data for
				; writes only)
	out	dx,al		;write the new AC Mode Control setting
				; with split screen pel panning
				; suppression turned on
endif
;
; Pel pan the non-split screen portion of the display; because
; split screen pel panning suppression is turned on, the split
; screen will not move as the pel panning setting cycles.
;
	mov	cx,200	;pan 200 pixels to the left
	call	PanRight
;
; Wait for a key press (don't echo character).
;
	mov	ah,8	;DOS console input without echo function
	int	21h
;
; Return to text mode and DOS.
;
	mov	ax,0003h	;AH=0 is select mode function
				;AL=3 is mode to select, text mode
	int	10h		;return to text mode
	mov	ah,4ch
	int	21h		;return to DOS
Start	endp
;*********************************************************************
; Waits for the leading edge of the vertical sync pulse.
;
; Input: none
;
; Output: none
;
; Registers altered: AL, DX
;
WaitForVerticalSyncStart	proc	near
	mov	dx,INPUT_STATUS_0
WaitNotVerticalSync:
	in	al,dx
	test	al,08h
	jnz	WaitNotVerticalSync
WaitVerticalSync:
	in	al,dx
	test	al,08h
	jz	WaitVerticalSync
	ret
WaitForVerticalSyncStart	endp
;*********************************************************************
; Waits for the trailing edge of the vertical sync pulse.
;
; Input: none
;
; Output: none
;
; Registers altered: AL, DX
;
WaitForVerticalSyncEnd	proc	near
	mov	dx,INPUT_STATUS_0
WaitVerticalSync2:
	in	al,dx
	test	al,08h
	jz	WaitVerticalSync2
WaitNotVerticalSync2:
	in	al,dx
	test	al,08h
	jnz	WaitNotVerticalSync2
	ret
WaitForVerticalSyncEnd	endp
;*********************************************************************
; Sets the start address to the value specifed by StartAddress.
; Wait for the trailing edge of vertical sync before setting so that
; one half of the address isn't loaded before the start of the frame
; and the other half after, resulting in flicker as one frame is
; displayed with mismatched halves. The new start address won't be
; loaded until the start of the next frame; that is, one full frame
; will be displayed before the new start address takes effect.
;
; Input: none
;
; Output: none
;
; Registers altered: AX, DX
;
SetStartAddress	proc	near
	call	WaitForVerticalSyncEnd
	mov	dx,CRTC_INDEX
	mov	al,START_ADDRESS_HIGH
	mov	ah,byte ptr [StartAddress+1]
	cli		;make sure both registers get set at once
	OUT_WORD
	mov	al,START_ADDRESS_LOW
	mov	ah,byte ptr [StartAddress]
	OUT_WORD
	sti
	ret
SetStartAddress	endp
;*********************************************************************
; Sets the horizontal pel panning setting to the value specified
; by PelPan. Waits until the start of vertical sync to do so, so
; the new pel pan setting can be loaded during non-display time
; and can be ready by the start of the next frame.
;
; Input: none
;
; Output: none
;
; Registers altered: AL, DX
;
SetPelPan	proc	near
	call	WaitForVerticalSyncStart ;also resets the AC
					; Index/Data toggle
					; to Index state
	mov	dx,AC_INDEX
	mov	al,PEL_PANNING+20h
				;bit 5 set to 1 to keep video on
	out	dx,al		;point the AC Index to Pel Pan reg
	mov	al,[PelPan]
	out	dx,al		;load the new Pel Pan setting
	ret
SetPelPan	endp
;*********************************************************************
; Sets the scan line the split screen starts after to the scan line
; specified by SplitScreenLine.
;
; Input: none
;
; Output: none
;
; All registers preserved
;
SetSplitScreenScanLine	proc	near
	push	ax
	push	cx
	push	dx
;
; Wait for the leading edge of the vertical sync pulse. This ensures
; that we don't get mismatched portions of the split screen setting
; while setting the two or three split screen registers (register 18h
; set but register 7 not yet set when a match occurs, for example),
; which could produce brief flickering.
;
	call	WaitForVerticalSyncStart
;
; Set the split screen scan line.
;
	mov	dx,CRTC_INDEX
	mov	ah,byte ptr [SplitScreenLine]
	mov	al,LINE_COMPARE
	cli		;make sure all the registers get set at once
	OUT_WORD		;set bits 7-0 of the split screen scan line
	mov		ah,byte ptr [SplitScreenLine+1]
	and	ah,1
	mov	cl,4
	shl	ah,cl	;move bit 8 of the split split screen scan
			; line into position for the Overflow reg
	mov	al,OVERFLOW
if IS_VGA
;
; The Split Screen, Overflow, and Line Compare registers all contain
; part of the split screen start scan line on the VGA. We'll take
; advantage of the readable registers of the VGA to leave other bits
; in the registers we access undisturbed.
;
	out	dx,al	;set CRTC Index reg to point to Overflow
	inc	dx	;point to CRTC Data reg
	in	al,dx	;get the current Overflow reg setting
	and	al,not 10h ;turn off split screen bit 8
	or	al,ah	;insert the new split screen bit 8
			; (works in any mode)
	out	dx,al	;set the new split screen bit 8
	dec	dx	;point to CRTC Index reg
	mov	ah,byte ptr [SplitScreenLine+1]
	and	ah,2
	mov	cl,3
	ror	ah,cl	;move bit 9 of the split split screen scan
			; line into position for the Maximum Scan
			; Line register
	mov	al,MAXIMUM_SCAN_LINE
	out	dx,al	;set CRTC Index reg to point to Maximum
			; Scan Line
	inc	dx	;point to CRTC Data reg
	in	al,dx	;get the current Maximum Scan Line setting
	and	al,not 40h ;turn off split screen bit 9
	or	al,ah	;insert the new split screen bit 9
			; (works in any mode)
	out	dx,al	;set the new split screen bit 9
else
;
; Only the Split Screen and Overflow registers contain part of the
; Split Screen start scan line and need to be set on the EGA.
; EGA registers are not readable, so we have to set the non-split
; screen bits of the Overflow register to a preset value, in this
; case the value for 350-scan-line modes.
;
	or	ah,0fh	;insert the new split screen bit 8
			; (only works in 350-scan-line EGA modes)
	OUT_WORD	;set the new split screen bit 8
endif
	sti
	pop	dx
	pop	cx
	pop	ax
	ret
SetSplitScreenScanLine	endp
;*********************************************************************
; Pan horizontally to the right the number of pixels specified by CX.
;
; Input: CX = # of pixels by which to pan horizontally
;
; Output: none
;
; Registers altered: AX, CX, DX
;
PanRight	proc	near
PanLoop:
	inc	[PelPan]
	and	[PelPan],07h
	jnz	DoSetStartAddress
	inc	[StartAddress]
DoSetStartAddress:
	call	SetStartAddress
	call	SetPelPan
	loop	PanLoop
	ret
PanRight	endp
;*********************************************************************
Code	ends
	end	Start
