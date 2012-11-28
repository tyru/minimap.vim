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

    let &titlestring = 'Slave pid:'.getpid().', Master pid:'.remote_expr(a:master_servername, 'getpid()')
    call s:fontzoom(5, 0)
endfunction


" from fontzoom.vim {{{
" https://github.com/thinca/vim-fontzoom

let s:FONTZOOM_PATTERN =
  \ has('win32') || has('win64') ||
  \ has('mac') || has('macunix') ? ':h\zs\d\+':
  \ has('gui_gtk') ? '\s\+\zs\d\+$':
  \ has('X11') ? '\v%([^-]*-){6}\zs\d+\ze%(-[^-]*){7}':
  \ '*Unknown system*'

function! s:change_fontsize(font, size)
    return join(map(split(a:font, '\\\@<!,'),
    \ printf('substitute(v:val, %s, %s, "g")',
    \ string(s:FONTZOOM_PATTERN),
    \ string('\=max([1,' . a:size . '])'))), ',')
endfunction

function! s:fontzoom(size, reset)
    if s:FONTZOOM_PATTERN ==# '*Unknown system*'
        echoerr 'minimap: Could not detect your environment.'
        return
    endif

    if a:reset
        if exists('s:keep') " Reset font size.
            let [&guifont, &guifontwide, &lines, &columns] = s:keep
            unlet! s:keep
        endif
    elseif a:size ==# ''
        echo matchstr(&guifont, s:FONTZOOM_PATTERN)
    else
        if !exists('s:keep')
            let s:keep = [&guifont, &guifontwide, &lines, &columns]
        endif
        let newsize = (a:size =~# '^[+-]' ? 'submatch(0)' : '') . a:size
        let &guifont = s:change_fontsize(&guifont, newsize)
        let &guifontwide = s:change_fontsize(&guifontwide, newsize)
    " Keep window size if possible.
        let [&lines, &columns] = s:keep[2 :]
    endif
endfunction

" }}}


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
