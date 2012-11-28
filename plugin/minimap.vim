" vim:foldmethod=marker:fen:
scriptencoding utf-8

" Load Once {{{
if (exists('g:loaded_minimap') && g:loaded_minimap) || &cp
    finish
endif
let g:loaded_minimap = 1
" }}}
" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}


command! -bar MinimapStart call minimap#start()
command! -bar MinimapStop  call minimap#stop()


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
