@_default:
    just --list

alias w := wake

wake:
    wake test wake_model -S ""
