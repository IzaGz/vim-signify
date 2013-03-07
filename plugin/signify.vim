" Copyright (c) 2013 Marco Hinz
" All rights reserved.
"
" Redistribution and use in source and binary forms, with or without
" modification, are permitted provided that the following conditions are met:
"
" - Redistributions of source code must retain the above copyright notice, this
"   list of conditions and the following disclaimer.
" - Redistributions in binary form must reproduce the above copyright notice,
"   this list of conditions and the following disclaimer in the documentation
"   and/or other materials provided with the distribution.
" - Neither the name of the author nor the names of its contributors may be
"   used to endorse or promote products derived from this software without
"   specific prior written permission.
"
" THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
" IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
" ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
" LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
" CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
" SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
" INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
" CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
" ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
" POSSIBILITY OF SUCH DAMAGE.

if exists('g:loaded_signify') || &cp
  finish
endif
let g:loaded_signify = 1

"  Default values  {{{1
" Overwrite non-signify signs by default
let s:line_highlight           = 0
let s:colors_set               = 0
let s:last_jump_was_next       = -1
let s:active_buffers           = {}
let s:other_signs_line_numbers = {}

let s:sign_overwrite = exists('g:signify_sign_overwrite') ? g:signify_sign_overwrite : 1

let s:id_start = 0x100
let s:id_top   = s:id_start
let s:id_jump  = s:id_start

"  Default mappings  {{{1
if exists('g:signify_mapping_next_hunk')
    exe 'nnoremap '. g:signify_mapping_next_hunk .' :SignifyJumpToNextHunk<cr>'
else
    nnoremap <leader>gn :SignifyJumpToNextHunk<cr>
endif

if exists('g:signify_mapping_prev_hunk')
    exe 'nnoremap '. g:signify_mapping_prev_hunk .' :SignifyJumpToPrevHunk<cr>'
else
    nnoremap <leader>gp :SignifyJumpToPrevHunk<cr>
endif

if exists('g:signify_mapping_toggle_highlight')
    exe 'nnoremap '. g:signify_mapping_toggle_highlight .' :SignifyToggleHighlight<cr>'
else
    nnoremap <leader>gh :SignifyToggleHighlight<cr>
endif

if exists('g:signify_mapping_toggle')
    exe 'nnoremap '. g:signify_mapping_toggle .' :SignifyToggle<cr>'
else
    nnoremap <leader>gt :SignifyToggle<cr>
endif

"  Default signs  {{{1
if exists('g:signify_sign_add')
    exe 'sign define SignifyAdd text='. g:signify_sign_add .' texthl=SignifyAdd linehl=none'
else
    sign define SignifyAdd text=+ texthl=SignifyAdd linehl=none
endif

if exists('g:signify_sign_delete')
    exe 'sign define SignifyDelete text='. g:signify_sign_delete .' texthl=SignifyDelete linehl=none'
else
    sign define SignifyDelete text=_ texthl=SignifyDelete linehl=none
endif

if exists('g:signify_sign_change')
    exe 'sign define SignifyChange text='. g:signify_sign_change .' texthl=SignifyChange linehl=none'
else
    sign define SignifyChange text=! texthl=SignifyChange linehl=none
endif

"  Initial stuff  {{{1
aug signify
    au!
    au ColorScheme              * call s:set_colors()
    au BufWritePost,FocusGained * call s:start()
    au BufEnter                 * let s:colors_set = 0 | call s:start()
    au BufDelete                * call s:stop() | call s:remove_from_buffer_list(expand('%:p'))
aug END

com! -nargs=0 -bar SignifyToggle          call s:toggle_signify()
com! -nargs=0 -bar SignifyToggleHighlight call s:toggle_line_highlighting()
com! -nargs=0 -bar SignifyJumpToNextHunk  call s:jump_to_next_hunk()
com! -nargs=0 -bar SignifyJumpToPrevHunk  call s:jump_to_prev_hunk()

"  Internal functions  {{{1
"  Functions -> s:start()  {{{2
function! s:start() abort
    let l:path = expand('%:p')

    if empty(l:path) || &ft == 'help'
        return
    endif

    " Check for exceptions.
    if exists('g:signify_exceptions_filetype')
        for i in g:signify_exceptions_filetype
            if i == &ft
                return
            endif
        endfor
    endif
    if exists('g:signify_exceptions_filename')
        for i in g:signify_exceptions_filename
            if i == expand('%')
                return
            endif
        endfor
    endif

    " New buffer.. add to list.
    if !has_key(s:active_buffers, l:path)
        let s:active_buffers[l:path] = { 'active': 1 }
    " Inactive buffer.. bail out.
    elseif s:active_buffers[l:path].active == 0
        return
    endif

    " Is a diff available?
    let diff = s:get_diff(l:path)
    if empty(diff)
        call s:remove_signs()
        return
    endif

    " Set colors only for the first time or when a new colorscheme is set.
    if !s:colors_set
        call s:set_colors()
        let s:colors_set = 1
    endif

    call s:remove_signs()
    let s:id_top = s:id_start

    if s:sign_overwrite == 0
        call s:get_other_signs(l:path)
    endif

    " Use git's diff cmd to set our signs.
    call s:process_diff(diff)
endfunction


"  Functions -> s:stop()  {{{2
function! s:stop() abort
    call s:remove_signs()
    aug signify
        au! * <buffer>
    aug END
endfunction

"  Functions -> s:toggle_signify()  {{{2
function! s:toggle_signify() abort
    let l:path = expand('%:p')
    if has_key(s:active_buffers, l:path) && (s:active_buffers[l:path].active == 1)
        call s:stop()
        let s:active_buffers[l:path].active = 0
    else
        let s:active_buffers[l:path].active = 1
        call s:start()
    endif
endfunction

"  Functions -> s:get_other_signs()  {{{2
function! s:get_other_signs(path) abort
    redir => signlist
        sil! exe ":sign place file=" . a:path
    redir END

    for line in split(signlist, '\n')
        if line =~ '^\s\+line'
            let s:other_signs_line_numbers[matchlist(line, '\v(\d+)')[1]] = 1
        endif
    endfor
endfunction

"  Functions -> s:set_sign()  {{{2
function! s:set_sign(lnum, type, path)
    " Preserve non-signify signs
    if get(s:other_signs_line_numbers, a:lnum) == 1
        return
    endif

    exe 'sign place '. s:id_top .' line='. a:lnum .' name='. a:type .' file='. a:path

    let s:id_top += 1
endfunction

"  Functions -> s:remove_signs()  {{{2
function! s:remove_signs() abort
    if s:sign_overwrite == 1
        sign unplace *
    else
        for id in range(s:id_start, s:id_top - 1)
            exe 'sign unplace '. id
        endfor
    endif
endfunction
"  Functions -> s:get_diff()  {{{2
function! s:get_diff(path) abort
    if !executable('grep')
        echoerr "signify: I cannot work without grep!"
        return
    endif

    if executable('git')
        let diff = system('git diff --no-ext-diff -U0 '. fnameescape(a:path) .'| grep "^@@ "')
        if !v:shell_error
            return diff
        endif
    endif

    if executable('hg')
        let diff = system('hg diff --nodates -U0 '. fnameescape(a:path) .'| grep "^@@ "')
        if !v:shell_error
            return diff
        endif
    endif

    if executable('diff')
        if executable('svn')
            let diff = system('svn diff --diff-cmd diff -x -U0 '. fnameescape(a:path) .'| grep "^@@ "')
            if !v:shell_error
                return diff
            endif
        endif

        if executable('bzr')
            let diff = system('bzr diff --using diff --diff-options=-U0 '. fnameescape(a:path) .'| grep "^@@ "')
            if !v:shell_error
                return diff
            endif
        endif
    endif

    if executable('cvs')
        let diff = system('cvs diff -U0 '. fnameescape(expand('%')) .' 2>&1 | grep "^@@ "')
        if !empty(diff)
            return diff
        endif
    endif

    return []
endfunction

"  Functions -> s:process_diff()  {{{2
function! s:process_diff(diff) abort
    let l:path = expand('%:p')

    " Determine where we have to put our signs.
    for line in split(a:diff, '\n')
        " Parse diff output.
        let tokens = matchlist(line, '\v^\@\@ -(\d+),?(\d*) \+(\d+),?(\d*)')
        if empty(tokens)
            echoerr 'signify: I cannot parse this line "'. line .'"'
        endif

        let [ old_line, old_count, new_line, new_count ] = [ str2nr(tokens[1]), (tokens[2] == '') ? 1 : str2nr(tokens[2]), str2nr(tokens[3]), (tokens[4] == '') ? 1 : str2nr(tokens[4]) ]

        " A new line was added.
        if (old_count == 0) && (new_count >= 1)
            let offset = 0
            while offset < new_count
                call s:set_sign(new_line + offset, 'SignifyAdd', l:path)
                let offset += 1
            endwhile
        " An old line was removed.
        elseif (old_count >= 1) && (new_count == 0)
            call s:set_sign(new_line, 'SignifyDelete', l:path)
        " A line was changed.
        elseif (old_count == new_count)
            let offset = 0
            while offset < new_count
                call s:set_sign(new_line + offset, 'SignifyChange', l:path)
                let offset += 1
            endwhile
        else
            " Lines were changed && deleted.
            if (old_count > new_count)
                let offset = 0
                while offset < new_count
                    call s:set_sign(new_line + offset, 'SignifyChange', l:path)
                    let offset += 1
                endwhile
                call s:set_sign(new_line + offset - 1, 'SignifyDelete', l:path)
            " (old_count < new_count): Lines were added && changed.
            else
                let offset = 0
                while offset < old_count
                    call s:set_sign(new_line + offset, 'SignifyChange', l:path)
                    let offset += 1
                endwhile
                while offset < new_count
                    call s:set_sign(new_line + offset, 'SignifyAdd', l:path)
                    let offset += 1
                endwhile
            endif
        endif
    endfor
endfunction

"  Functions -> s:set_colors()  {{{2
func! s:set_colors() abort
    if has('gui_running')
        let guifg_add    = exists('g:signify_color_sign_guifg_add')    ? g:signify_color_sign_guifg_add    : '#11ee11'
        let guifg_delete = exists('g:signify_color_sign_guifg_delete') ? g:signify_color_sign_guifg_delete : '#ee1111'
        let guifg_change = exists('g:signify_color_sign_guifg_change') ? g:signify_color_sign_guifg_change : '#eeee11'

        if exists('g:signify_color_sign_guibg')
            let guibg = g:signify_color_sign_guibg
        endif

        if !exists('guibg')
            let guibg = synIDattr(hlID('LineNr'), 'bg', 'gui')
        endif

        if empty(guibg) || guibg < 0
            exe 'hi SignifyAdd    gui=bold guifg='. guifg_add
            exe 'hi SignifyDelete gui=bold guifg='. guifg_delete
            exe 'hi SignifyChange gui=bold guifg='. guifg_change
        else
            exe 'hi SignifyAdd    gui=bold guifg='. guifg_add    .' guibg='. guibg
            exe 'hi SignifyDelete gui=bold guifg='. guifg_delete .' guibg='. guibg
            exe 'hi SignifyChange gui=bold guifg='. guifg_change .' guibg='. guibg
        endif
    else
        let ctermfg_add    = exists('g:signify_color_sign_ctermfg_add')    ? g:signify_color_sign_ctermfg_add    : 2
        let ctermfg_delete = exists('g:signify_color_sign_ctermfg_delete') ? g:signify_color_sign_ctermfg_delete : 1
        let ctermfg_change = exists('g:signify_color_sign_ctermfg_change') ? g:signify_color_sign_ctermfg_change : 3

        if exists('g:signify_color_sign_ctermbg')
            let ctermbg = g:signify_color_sign_ctermbg
        endif

        if !exists('ctermbg')
            let ctermbg = synIDattr(hlID('LineNr'), 'bg', 'cterm')
        endif

        if empty(ctermbg) || ctermbg < 0
            exe 'hi SignifyAdd    cterm=bold ctermfg='. ctermfg_add
            exe 'hi SignifyDelete cterm=bold ctermfg='. ctermfg_delete
            exe 'hi SignifyChange cterm=bold ctermfg='. ctermfg_change
        else
            exe 'hi SignifyAdd    cterm=bold ctermfg='. ctermfg_add    .' ctermbg='. ctermbg
            exe 'hi SignifyDelete cterm=bold ctermfg='. ctermfg_delete .' ctermbg='. ctermbg
            exe 'hi SignifyChange cterm=bold ctermfg='. ctermfg_change .' ctermbg='. ctermbg
        endif
    endif
endfunc

"  Functions -> s:toggle_line_highlighting()  {{{2
function! s:toggle_line_highlighting() abort
    if s:line_highlight
        sign define SignifyAdd    text=+ texthl=SignifyAdd    linehl=none
        sign define SignifyDelete text=_ texthl=SignifyDelete linehl=none
        sign define SignifyChange text=! texthl=SignifyChange linehl=none
        let s:line_highlight = 0
    else
        let add    = exists('g:signify_color_line_highlight_add')    ? g:signify_color_line_highlight_add    : 'DiffAdd'
        let delete = exists('g:signify_color_line_highlight_delete') ? g:signify_color_line_highlight_delete : 'DiffDelete'
        let change = exists('g:signify_color_line_highlight_change') ? g:signify_color_line_highlight_change : 'DiffChange'

        exe 'sign define SignifyAdd    text=+ texthl=SignifyAdd    linehl='. add
        exe 'sign define SignifyDelete text=_ texthl=SignifyDelete linehl='. delete
        exe 'sign define SignifyChange text=! texthl=SignifyChange linehl='. change
        let s:line_highlight = 1
    endif
    call s:start()
endfunction

"  Functions -> s:jump_to_next_hunk()  {{{2
function! s:jump_to_next_hunk()
    if s:last_jump_was_next == 0
        let s:id_jump += 2
    endif
    exe 'sign jump '. s:id_jump .' file='. expand('%:p')
    let s:id_jump = (s:id_jump == (s:id_top - 1)) ? (s:id_start) : (s:id_jump + 1)
    let s:last_jump_was_next = 1
endfunction

"  Functions -> s:jump_to_prev_hunk()  {{{2
function! s:jump_to_prev_hunk()
    if s:last_jump_was_next == 1
        let s:id_jump -= 2
    endif
    exe 'sign jump '. s:id_jump .' file='. expand('%:p')
    let s:id_jump = (s:id_jump == s:id_start) ? (s:id_top - 1) : (s:id_jump - 1)
    let s:last_jump_was_next = 0
endfunction

"  Functions -> s:remove_from_buffer_list()  {{{2
function! s:remove_from_buffer_list(path) abort
    if has_key(s:active_buffers, a:path)
        call remove(s:active_buffers, a:path)
    endif
endfunction

"  Functions -> SignifyDebugListActiveBuffers()  {{{2
function! SignifyDebugListActiveBuffers() abort
    if len(s:active_buffers) == 0
        echo 'No active buffers!'
        return
    endif

    for i in items(s:active_buffers)
        echo i
    endfor
endfunction

"  Functions -> SignifyDebugID()  {{{2
function! SignifyDebugID() abort
    echo [ s:id_start, s:id_top ]
endfunction
