map <Tab> :b#<CR>

"highlight OverLength ctermbg=red ctermfg=white guibg=#592929
"match OverLength /\%81v.\+/

"highlight ColorColumn ctermbg=grey
"set colorcolumn=80

" Arcadia plugins
let g:ya_vim#use_plugin#fswitch = 'yes'

" YouCompleteMe
nnoremap <Leader>s :%s/\<<C-r><C-w>\>/
nnoremap <Leader>g :YcmCompleter GoTo<CR>
nnoremap <Leader>t  :YcmCompleter GetType<CR>
nnoremap <Leader>p  :YcmCompleter GetParent<CR>

let g:ycm_confirm_extra_conf = 0
let g:ycm_show_diagnostics_ui = 0

nnoremap <Leader>h :FSSplitLeft<CR>

"nnoremap <Leader>l :set colorcolumn=80<CR>
"nnoremap <Leader>lo :set colorcolumn=0<CR>

" How to learn hjkl
"nnoremap <Up>     <NOP>
"nnoremap <Down>   <NOP>
"nnoremap <Left>   <NOP>
"nnoremap <Right>  <NOP>

" Alt + left/right
"nmap <Esc>[1;3D :call TabManagment_tab_prev()<CR>
"nmap <Esc>[1;3C :call TabManagment_tab_next()<CR>
nmap <F9>  :call TabManagment_tab_prev()<CR>
nmap <F10> :call TabManagment_tab_next()<CR>

syntax on

"set number

set smartindent
set expandtab 
set softtabstop=4
set shiftwidth=4

set guioptions-=T
set vb t_vb=
set ruler

set showmatch " jump to the another bracket, when bracket is inserted
set hls
set incsearch " 'partial' search (no word boundaries)

set autowrite
set backspace=2 " make backspace work like most other apps
"set pastetoggle=<F8> " Easily copy from clipboard

set fileencodings=utf-8

" Disable preview window
set completeopt-=preview

let g:localvimrc_ask=0

" Задаем собственные функции для назначения имен заголовкам табов -->
    function MyTabLine()
        let tabline = ''

        " Формируем tabline для каждой вкладки -->
            for i in range(tabpagenr('$'))
                " Подсвечиваем заголовок выбранной в данный момент вкладки.
                if i + 1 == tabpagenr()
                    let tabline .= '%#TabLineSel#'
                else
                    let tabline .= '%#TabLine#'
                endif

                " Устанавливаем номер вкладки
                let tabline .= '%' . (i + 1) . 'T'

                " Получаем имя вкладки
                let tabline .= ' %{MyTabLabel(' . (i + 1) . ')} |'
            endfor
        " Формируем tabline для каждой вкладки <--

        " Заполняем лишнее пространство
        let tabline .= '%#TabLineFill#%T'

        " Выровненная по правому краю кнопка закрытия вкладки
        if tabpagenr('$') > 1
            let tabline .= '%=%#TabLine#%999XX'
        endif

        return tabline
    endfunction

    function MyTabLabel(n)
        let label = ''
        let buflist = tabpagebuflist(a:n)

        " Имя файла и номер вкладки -->
            let label = substitute(bufname(buflist[tabpagewinnr(a:n) - 1]), '.*/', '', '')

            if label == ''
                let label = '[No Name]'
            endif

            let label .= ' (' . a:n . ')'
        " Имя файла и номер вкладки <--

        " Определяем, есть ли во вкладке хотя бы один
        " модифицированный буфер.
        " -->
            for i in range(len(buflist))
                if getbufvar(buflist[i], "&modified")
                    let label = '[+] ' . label
                    break
                endif
            endfor
        " <--

        return label
    endfunction

    function MyGuiTabLabel()
        return '%{MyTabLabel(' . tabpagenr() . ')}'
    endfunction

    set tabline=%!MyTabLine()
    set guitablabel=%!MyGuiTabLabel()
" Задаем собственные функции для назначения имен заголовкам табов <--


function! TabManagment_tab_next()
    if tabpagenr() < tabpagenr('$')
        tabnext
    endif
endfunction


function! TabManagment_tab_prev()
    if tabpagenr() > 1
        tabprev
    endif
endfunction

" ~/.vimrc ends here
