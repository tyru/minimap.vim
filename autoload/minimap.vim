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
        call self.force_stop()
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

function! s:Minimap.force_stop()
    if self.has_server(self._slave_srvname)
        throw 'minimap: Could not force stop; '.string(self._slave_srvname).' is not responding but alive'
    endif
    let self._state = s:STATE_STOPPED
    let self._slave_srvname = ''

    echomsg 'forcefully stopping a previous slave ... done.'
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

    " Let a slave server open a same file.
    augroup minimap
        autocmd BufReadPost * call s:Minimap.sendexcmd('edit! `='.string(expand('<afile>')).'`')
    augroup END
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
    if self._state is s:STATE_STOPPING
        try
            call self.force_stop()
        catch
            " A slave server is alive. continue...
        endtry
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
        PP! printf('silent !%s %s', command, join(cmdargs))
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
