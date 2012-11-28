" vim:foldmethod=marker:fen:
scriptencoding utf-8

" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}


function! minimap#load()
    " dummy function to load this script.
endfunction

function! minimap#start()
    call s:Minimap.start()
endfunction

function! minimap#stop()
    call s:Minimap.stop()
endfunction

function! minimap#_slave_started(slave_servername)
    call s:Minimap.on_slave_started(a:slave_servername)
endfunction

function! minimap#_slave_stopped(slave_servername)
    call s:Minimap.on_slave_stopped(a:slave_servername)
endfunction


let s:STATE_STOPPED  = 0   " a slave server does not exist.
let s:STATE_STARTING = 1   " starting a slave server...
let s:STATE_STARTED  = 2   " a slave server replied
let s:STATE_STOPPING = 3   " stopping a slave server...
let s:Minimap = {
\   '_state': s:STATE_STOPPED,
\   '_slave_srvname': '',
\   '_callback': 's:nop',
\}

function! s:Minimap.start()
    if self._state is s:STATE_STARTING
    \   && self.has_server(self._slave_srvname)
        call s:error('minimap: Could not start; '.string(self._slave_srvname).' is not responding but alive')
        let self._state = s:STATE_STOPPED
        let self._slave_srvname = ''
        return
    endif
    if self._state isnot s:STATE_STOPPED
        return
    endif

    " Register RemoteReply auto-command and callback.
    " (RemoteReply -> callback)
    augroup minimap
        autocmd!
        autocmd RemoteReply *
            \ call s:Minimap.invoke_callback(expand('<amatch>'), expand('<afile>'))
    augroup END

    " Spawn a slave server.
    let srvname = self.generate_available_servername()
    let slave_start_script = s:get_slave_start_script()
    call s:spawn(['gvim', '--servername', srvname, '-S', slave_start_script, '-c', 'call SlaveStarted('.string(v:servername).')'])
    let self._state = s:STATE_STARTING
    let self._slave_srvname = srvname
endfunction

function! s:get_slave_start_script()
    let script = get(split(globpath(&rtp, 'macros/minimap_slave_start.vim'), '\n'), 0, '')
    if script ==# ''
        throw 'minimap: Could not find macros/minimap_slave_start.vim in your runtimepath.'
    endif
    return script
endfunction

function! s:get_slave_stop_script()
    let script = get(split(globpath(&rtp, 'macros/minimap_slave_stop.vim'), '\n'), 0, '')
    if script ==# ''
        throw 'minimap: Could not find macros/minimap_slave_stop.vim in your runtimepath.'
    endif
    return script
endfunction

function! s:Minimap.on_slave_started(slave_servername)
    call server2client(expand('<client>'), 'SYN/ACK')
    let self._state = s:STATE_STARTED
    let self._slave_srvname = a:slave_servername

    " If a master quits, a slave also quits.
    augroup minimap
        autocmd VimLeavePre * call s:Minimap.stop()
    augroup END

    " Let a slave server open a same file.
    augroup minimap
        autocmd BufReadPost,BufEnter *
        \     if filereadable(expand('<afile>'))
        \   |     call s:Minimap.sendexcmd('edit! `='.string(fnamemodify(expand('<afile>'), ':p')).'`')
        \   | endif
    augroup END

    " Let a slave server sync a view of a current file.
    augroup minimap
        autocmd CursorMoved *
        \   call s:Minimap.sendexcmd('call winrestview('.string(winsaveview()).')')
    augroup END

    call self.align_to_right()

    " Make a master Vim foreground.
    call foreground()
endfunction

function! s:Minimap.align_to_left()
    " TODO
    echoerr 's:Minimap.align_to_left() is not implemented yet!'
endfunction

function! s:Minimap.align_to_right()
    if !executable('xwininfo') || !exists('$WINDOWID')
        call s:error('minimap: Cannot align to right (need ''xwininfo'' and $WINDOWID)')
        call s:warn('minimap: fallback to aligning to left...')
        sleep 2
        return self.align_to_left()
    endif

    " Get master Vim's GUI window width.
    let xwininfo = system('xwininfo -id $WINDOWID')
    let rx_width = 'Width: \(\d\+\)'
    let master_width = get(matchlist(get(filter(split(xwininfo, '\n'), 'v:val =~# rx_width'), 0, ''), rx_width), 1, '')
    if master_width ==# ''
        call s:error('minimap: Cannot get a GUI window width.')
        call s:warn('minimap: fallback to aligning to left...')
        sleep 2
        return self.align_to_left()
    endif

    return
    " Make a space for a slave Vim.
    let SLAVE_GVIM_WIDTH = 25    " TODO: SLAVE_GVIM_WIDTH -> global variable
    let &columns -= SLAVE_GVIM_WIDTH

    " Let a slave Vim align to a master Vim.
    call self.sendexcmd('set columns='.SLAVE_GVIM_WIDTH)
    call self.sendexcmd('set lines='.&lines)
    " TODO: Support MacVim :winpos x,y flipped bug?
    " call self.sendexcmd(printf('silent winpos %d %d', getwinposx()+master_width, getwinposy()))
    call self.sendexcmd(printf('silent winpos %d %d', master_width-SLAVE_GVIM_WIDTH, getwinposy()))
endfunction

function! s:Minimap.on_slave_stopped(slave_servername)
    call server2client(expand('<client>'), 'FIN/ACK')
    let self._state = s:STATE_STOPPED
    let self._slave_srvname = ''
endfunction

function! s:Minimap.register_callback(callback)
    let self._callback = a:callback
endfunction

function! s:nop(...)
    echom 'called s:nop()'
    sleep 2
    redraw
endfunction

function! s:Minimap.stop()
    if !self.has_server(self._slave_srvname)
        call self.slave_finalize()
        return
    endif
    if self._state is s:STATE_STOPPED
        return
    endif

    " Kill a slave server.
    let slave_stop_script = s:get_slave_stop_script()
    call self.sendexcmd('source '.slave_stop_script)
    call self.sendexcmd('call SlaveStopped('.string(v:servername).')')
    call self.sendexcmd('qa!')
    let self._state = s:STATE_STOPPING
endfunction

function! s:Minimap.invoke_callback(serverid, response_text)
    return call(self._callback, [a:serverid, a:response_text])
endfunction

function! s:Minimap.generate_available_servername()
    let srvname = v:servername.'-MINIMAP'
    let i = 1
    while self.has_server(srvname)
        let srvname = v:servername.'-MINIMAP'.i
    endwhile
    return srvname
endfunction

function! s:Minimap.has_server(srvname)
    return !empty(filter(split(serverlist(), '\n'), 'v:val ==# a:srvname'))
endfunction

function! s:Minimap.send(string, ...)
    return call('remote_send', [self._slave_srvname, a:string] + a:000)
endfunction

function! s:Minimap.sendexcmd(string, ...)
    let string = printf('<C-\><C-g>:<C-u>%s<CR>', a:string)
    return call(self.send, [string] + a:000, self)
endfunction

function! s:error(msg)
    echohl Error
    try
        echomsg a:msg
    finally
        echohl None
    endtry
endfunction

function! s:warn(msg)
    echohl WarningMsg
    try
        echomsg a:msg
    finally
        echohl None
    endtry
endfunction

" from restart.vim {{{
let s:is_win = has('win16') || has('win32') || has('win64')

function! s:spawn(args)
    let [command; cmdargs] = map(copy(a:args), 's:shellescape(v:val)')
    if s:is_win
        " NOTE: If a:command is .bat file,
        " cmd.exe appears and won't close.
        execute printf('silent !start %s %s', command, join(cmdargs))
    elseif has('gui_macvim')
        macaction newWindow:
    else
        execute printf('silent !%s %s', command, join(cmdargs))
    endif
endfunction

function! s:shellescape(...) "{{{
    if s:is_win
        let save_shellslash = &shellslash
        let &l:shellslash = 0
        try
            return call('shellescape', a:000)
        finally
            let &l:shellslash = save_shellslash
        endtry
    else
        return call('shellescape', a:000)
    endif
endfunction "}}}
" }}}




" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
