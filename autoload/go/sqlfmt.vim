" Copyright 2011 The Go Authors. All rights reserved.
" Use of this source code is governed by a BSD-style
" license that can be found in the LICENSE file.
"
" sqlfmt.vim: Vim command to format Go files with go-sqlfmt 

" don't spam the user when Vim is started in Vi compatibility mode
let s:cpo_save = &cpo
set cpo&vim

function! go#sqlfmt#Format() abort
  " Write current unsaved buffer to a temp file
  let l:tmpname = tempname() . '.go'
  call writefile(go#util#GetLines(), l:tmpname)
  if go#util#IsWin()
    let l:tmpname = tr(l:tmpname, '\', '/')
  endif

  let bin_name = go#config#SqlFmtCommand()
  let current_col = col('.')
  let [l:out, l:err] = go#sqlfmt#run(bin_name, l:tmpname, expand('%'))
  let diff_offset = len(readfile(l:tmpname)) - line('$')

  if l:err == 0
    call go#sqlfmt#update_file(l:tmpname, expand('%'))
  elseif !go#config#SqlFmtFailSilently()
    let errors = s:parse_errors(expand('%'), out)
    call s:show_errors(errors)
  endif

  " We didn't use the temp file, so clean up
  call delete(l:tmpname)

  " be smart and jump to the line the new statement was added/removed
  call cursor(line('.') + diff_offset, current_col)

  " Syntax highlighting breaks less often.
  syntax sync fromstart
endfunction

function! go#sqlfmt#run(bin_name, source, target)
  let l:cmd = [a:bin_name, '-s', a:target, '-o', a:source]
  if empty(l:cmd)
    return
  endif
  return go#util#Exec(l:cmd)
endfunction

" update_file updates the target file with the given formatted source
function! go#sqlfmt#update_file(source, target)
  " remove undo point caused via BufWritePre
  try | silent undojoin | catch | endtry

  let old_fileformat = &fileformat
  if exists("*getfperm")
    " save file permissions
    let original_fperm = getfperm(a:target)
  endif

  call rename(a:source, a:target)

  " restore file permissions
  if exists("*setfperm") && original_fperm != ''
    call setfperm(a:target , original_fperm)
  endif

  " reload buffer to reflect latest changes
  silent edit!

  let &fileformat = old_fileformat
  let &syntax = &syntax

  let l:listtype = go#list#Type("GoSqlFmt")

  " the title information was introduced with 7.4-2200
  " https://github.com/vim/vim/commit/d823fa910cca43fec3c31c030ee908a14c272640
  if has('patch-7.4.2200')
    " clean up previous list
    if l:listtype == "quickfix"
      let l:list_title = getqflist({'title': 1})
    else
      let l:list_title = getloclist(0, {'title': 1})
    endif
  else
    " can't check the title, so assume that the list was for sqlfmt.
    let l:list_title = {'title': 'SqlFormat'}
  endif

  if has_key(l:list_title, "title") && l:list_title['title'] == "SqlFormat"
    call go#list#Clean(l:listtype)
  endif
endfunction

" show_errors opens a location list and shows the given errors. If the given
" errors is empty, it closes the the location list
function! s:show_errors(errors) abort
  let l:listtype = go#list#Type("GoSqlFmt")
  if !empty(a:errors)
    call go#list#Populate(l:listtype, a:errors, 'SqlFormat')
    echohl Error | echomsg "GoSqlfmt returned error" | echohl None
  endif

  " this closes the window if there are no errors or it opens
  " it if there is any
  call go#list#Window(l:listtype, len(a:errors))
endfunction

function! go#sqlfmt#ToggleSqlFmtAutoSave() abort
  if go#config#SqlFmtAutosave()
    call go#config#SetSqlFmtAutosave(0)
    call go#util#EchoProgress("auto sqlfmt disabled")
    return
  end

  call go#config#SetSqlFmtAutosave(1)
  call go#util#EchoProgress("auto sqlfmt enabled")
endfunction

" restore Vi compatibility settings
let &cpo = s:cpo_save
unlet s:cpo_save

" vim: sw=2 ts=2 et
