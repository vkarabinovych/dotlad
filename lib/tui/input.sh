# shellcheck shell=bash disable=SC2034  # timeouts are consumed by tui.sh
# lib/tui/input.sh — keyboard input and layout normalization for the picker.

TUI_KEY=""
# Bash 3.2 accepts only whole seconds for `read -t`.
TUI_FRAME_TIMEOUT="0.15"
TUI_SEQUENCE_TIMEOUT="0.05"
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    TUI_FRAME_TIMEOUT=1
    TUI_SEQUENCE_TIMEOUT=1
fi

# Stock macOS Bash 3.2 reads Cyrillic as two bytes even in a UTF-8 locale.
# Join that pair so the Ukrainian aliases in the key dispatch can match.
tui_read_key() {
    local timeout="${1:-}" first="" second=""
    TUI_KEY=""
    if [[ -n "$timeout" ]]; then
        IFS= read -rsn1 -t "$timeout" first || return 1
    else
        IFS= read -rsn1 first || return 1
    fi
    TUI_KEY="$first"
    case "$first" in
        $'\320' | $'\321')
            IFS= read -rsn1 second || {
                TUI_KEY=""
                return 1
            }
            TUI_KEY+="$second"
            ;;
    esac
    return 0
}

# Normalize Ukrainian-layout characters by their physical Latin key so every
# letter shortcut works without switching layouts.
tui_normalize_key() {
    local k=$TUI_KEY
    case $k in
        й) k=q ;; ц) k=w ;; у) k=e ;; к) k=r ;; е) k=t ;; н) k=y ;;
        г) k=u ;; ш) k=i ;; щ) k=o ;; з) k=p ;; х) k='[' ;; ї) k=']' ;;
        ф) k=a ;; і) k=s ;; в) k=d ;; а) k=f ;; п) k=g ;; р) k=h ;;
        о) k=j ;; л) k=k ;; д) k=l ;; ж) k=';' ;; є) k="'" ;;
        я) k=z ;; ч) k=x ;; с) k=c ;; м) k=v ;; и) k=b ;; т) k=n ;;
        ь) k=m ;; б) k=',' ;; ю) k='.' ;;
        Й) k=Q ;; Ц) k=W ;; У) k=E ;; К) k=R ;; Е) k=T ;; Н) k=Y ;;
        Г) k=U ;; Ш) k=I ;; Щ) k=O ;; З) k=P ;; Х) k='{' ;; Ї) k='}' ;;
        Ф) k=A ;; І) k=S ;; В) k=D ;; А) k=F ;; П) k=G ;; Р) k=H ;;
        О) k=J ;; Л) k=K ;; Д) k=L ;; Ж) k=':' ;; Є) k='"' ;;
        Я) k=Z ;; Ч) k=X ;; С) k=C ;; М) k=V ;; И) k=B ;; Т) k=N ;;
        Ь) k=M ;; Б) k='<' ;; Ю) k='>' ;;
        ґ) k='`' ;; Ґ) k='~' ;;
    esac
    TUI_KEY=$k
}
