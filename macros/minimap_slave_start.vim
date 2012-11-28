" vim:foldmethod=marker:fen:
scriptencoding utf-8

" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}


function! SlaveStarted(master_servername)
    augroup minimap-slave
        autocmd!
        autocmd RemoteReply *
        \     if remote_read(expand('<amatch>')) !=# 'SYN/ACK'
        \   |     echoerr 'minimap: master server '.string(a:master_servername).' returned a invalid string.'
        \   | endif
    augroup END
    call remote_send(a:master_servername, '<C-\><C-g><C-l>:<C-u>call minimap#_slave_started('.string(v:servername).')<CR><C-l>')
endfunction


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
