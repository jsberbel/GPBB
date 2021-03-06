; *** Listing 6.1 ***
;
; Program to illustrate the use of the Read Map register in read mode 0.
; Animates by copying a 16-color image from VGA memory to system memory,
; one plane at a time, then copying the image back to a new location
; in VGA memory.
;
; Assembled with TASM 4.0, linked with TLINK 6.10
; Checked by Jim Mischel 11/21/94
;
stack	segment	word stack 'STACK'
	db	512 dup (?)
stack	ends
;
data	segment	word 'DATA'
IMAGE_WIDTH	EQU	4	;in bytes
IMAGE_HEIGHT	EQU	32	;in pixels
LEFT_BOUND	EQU	10	;in bytes
RIGHT_BOUND	EQU	66	;in bytes
VGA_SEGMENT	EQU	0a000h
SCREEN_WIDTH	EQU	80	;in bytes
SC_INDEX		EQU	3c4h	;Sequence Controller Index register
GC_INDEX		EQU	3ceh	;Graphics Controller Index register
MAP_MASK		EQU	2	;Map Mask register index in SC
READ_MAP		EQU	4	;Read Map register index in GC
;
; Base pattern for 16-color image.
;
PatternPlane0	label	byte
	db	32 dup (0ffh,0ffh,0,0)
PatternPlane1	label	byte
	db	32 dup (0ffh,0,0ffh,0)
PatternPlane2	label	byte
	db	32 dup (0f0h,0f0h,0f0h,0f0h)
PatternPlane3	label	byte
	db	32 dup (0cch,0cch,0cch,0cch)
;
; Temporary storage for 16-color image during animation.
;
ImagePlane0	db	32*4 dup (?)
ImagePlane1	db	32*4 dup (?)
ImagePlane2	db	32*4 dup (?)
ImagePlane3	db	32*4 dup (?)
;
; Current image location & direction.
;
ImageX		dw	40	;in bytes
ImageY		dw	100	;in pixels
ImageXDirection	dw	1	;in bytes
data	ends
;
code	segment	word 'CODE'
	assume	cs:code,ds:data
Start	proc	near
	cld
	mov	ax,data
	mov	ds,ax
;
; Select graphics mode 10h.
;
	mov	ax,10h
	int	10h
;
; Draw the initial image.
;
	mov	si,offset PatternPlane0
	call	DrawImage
;
; Loop to animate by copying the image from VGA memory to system memory,
; erasing the image, and copying the image from system memory to a new
; location in VGA memory. Ends when a key is hit.
;
AnimateLoop:
;
; Copy the image from VGA memory to system memory.
;
	mov	di,offset ImagePlane0
	call	GetImage
;
; Clear the image from VGA memory.
;
	call	EraseImage
;
; Advance the image X coordinate, reversing direction if either edge
; of the screen has been reached.
;
	mov	ax,[ImageX]
	cmp	ax,LEFT_BOUND
	jz	ReverseDirection
	cmp	ax,RIGHT_BOUND
	jnz	SetNewX
ReverseDirection:
	neg	[ImageXDirection]
SetNewX:
	add	ax,[ImageXDirection]
	mov	[ImageX],ax
;
; Draw the image by copying it from system memory to VGA memory.
;
	mov	si,offset ImagePlane0
	call	DrawImage
;
; Slow things down a bit for visibility (adjust as needed).
;
	mov	cx,0
DelayLoop:
	loop	DelayLoop
;
; See if a key has been hit, ending the program.
;
	mov	ah,1
	int	16h
	jz	AnimateLoop
;
; Clear the key, return to text mode, and return to DOS.
;
	sub	ah,ah
	int	16h
	mov	ax,3
	int	10h
	mov	ah,4ch
	int	21h
Start	endp
;
; Draws the image at offset DS:SI to the current image location in
; VGA memory.
;
DrawImage	proc	near
	mov	ax,VGA_SEGMENT
	mov	es,ax
	call	GetImageOffset	;ES:DI is the destination address for the
				; image in VGA memory
	mov	dx,SC_INDEX
	mov	al,1		;do plane 0 first
DrawImagePlaneLoop:
	push	di		;image is drawn at the same offset in
				; each plane
	push	ax		;preserve plane select
	mov	al,MAP_MASK	;Map Mask index
	out	dx,al		;point SC Index to the Map Mask register
	pop	ax		;get back plane select
	inc	dx		;point to SC index register
	out	dx,al		;set up the Map Mask to allow writes to
				; the plane of interest
	dec	dx		;point back to SC Data register
	mov	bx,IMAGE_HEIGHT	;# of scan lines in image
DrawImageLoop:
	mov	cx,IMAGE_WIDTH	;# of bytes across image
	rep	movsb
	add	di,SCREEN_WIDTH-IMAGE_WIDTH
				;point to next scan line of image
	dec	bx		;any more scan lines?
	jnz	DrawImageLoop
	pop	di		;get back image start offset in VGA memory
	shl	al,1		;Map Mask setting for next plane
	cmp	al,10h		;have we done all four planes?
	jnz	DrawImagePlaneLoop
	ret
DrawImage	endp
;
; Copies the image from its current location in VGA memory into the
; buffer at DS:DI.
;
GetImage	proc	near
	mov	si,di		;move destination offset into SI
	call	GetImageOffset	;DI is offset of image in VGA memory
	xchg	si,di		;SI is offset of image, DI is destination offset
	push	ds
	pop	es		;ES:DI is destination
	mov	ax,VGA_SEGMENT
	mov	ds,ax		;DS:SI is source
;
	mov	dx,GC_INDEX
	sub	al,al		;do plane 0 first
GetImagePlaneLoop:
	push	si		;image comes from same offset in each plane
	push	ax		;preserve plane select
	mov	al,READ_MAP	;Read Map index
	out	dx,al		;point GC Index to Read Map register
	pop	ax		;get back plane select
	inc	dx		;point to GC Index register
	out	dx,al		;set up the Read Map to select reads from
				; the plane of interest
	dec	dx		;point back to GC data register
	mov	bx,IMAGE_HEIGHT	;# of scan lines in image
GetImageLoop:
	mov	cx,IMAGE_WIDTH	;# of bytes across image
	rep	movsb
	add	si,SCREEN_WIDTH-IMAGE_WIDTH
				;point to next scan line of image
	dec	bx		;any more scan lines?
	jnz	GetImageLoop
	pop	si		;get back image start offset
	inc	al		;Read Map setting for next plane
	cmp	al,4		;have we done all four planes?
	jnz	GetImagePlaneLoop
	push	es
	pop	ds		;restore original DS
	ret
GetImage	endp
;
; Erases the image at its current location.
;
EraseImage	proc	near
	mov	dx,SC_INDEX
	mov	al,MAP_MASK
	out	dx,al		;point SC Index to the Map Mask register
	inc	dx		;point to SC Data register
	mov	al,0fh
	out	dx,al		;set up the Map Mask to allow writes to go to
				; all 4 planes
	mov	ax,VGA_SEGMENT
	mov	es,ax
	call	GetImageOffset	;ES:DI points to the start address
				; of the image
	sub	al,al		;erase with zeros
	mov	bx,IMAGE_HEIGHT	;# of scan lines in image
EraseImageLoop:
	mov	cx,IMAGE_WIDTH	;# of bytes across image
	rep	stosb
	add	di,SCREEN_WIDTH-IMAGE_WIDTH
				;point to next scan line of image
	dec	bx		;any more scan lines?
	jnz	EraseImageLoop
	ret
EraseImage	endp
;
; Returns the current offset of the image in the VGA segment in DI.
;
GetImageOffset	proc	near
	mov	ax,SCREEN_WIDTH
	mul	[ImageY]
	add	ax,[ImageX]
	mov	di,ax
	ret
GetImageOffset	endp
code	ends
	end	Start
