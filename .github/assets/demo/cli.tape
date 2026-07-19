# Dotlad's standalone README demo. Run from the repository root with:
# vhs .github/assets/demo/cli.tape

Require bash
Require git

Output .github/assets/demo/cli.gif

Set Shell "bash"
Set FontFamily "FiraCode Nerd Font"
Set FontSize 15
Set Width 960
Set Height 420
Set Padding 14
Set Theme "Dracula+"
Set TypingSpeed 55ms

Hide
Type@1ms "export DOTLAD_DEMO_ROOT=/tmp/dotlad-readme-demo" Enter
Type@1ms "export DOTLAD_RUNTIME=$PWD" Enter
Type@1ms "/bin/bash .github/assets/demo/setup.sh" Enter
Type@1ms "export HOME=$DOTLAD_DEMO_ROOT/home" Enter
Type@1ms "export PATH=$DOTLAD_DEMO_ROOT/bin:$DOTLAD_DEMO_ROOT/brew/bin:$DOTLAD_RUNTIME:$PATH" Enter
Type@1ms "export DOTLAD_FORCE_COLOR=1 DOTLAD_SHOW_KEYS=1 TERM=xterm-256color COLORTERM=truecolor" Enter
Type@1ms "cd $DOTLAD_DEMO_ROOT/project" Enter
Ctrl+L
Sleep 1s
Show

Type "dotlad" Sleep 400ms Enter
Wait+Screen@30s /update available/
Sleep 3s

Space
Sleep 1s
Down
Sleep 1s
Type "m"
Sleep 3s
Type "m"
Sleep 3s
Type "m"
Sleep 2s

Type "g"
Sleep 1s
Type "d"
Sleep 3s
Type "q"
Sleep 2s
Hide
Type "q"
Sleep 1s
Type@1ms "cd /tmp && rm -rf $DOTLAD_DEMO_ROOT" Enter
