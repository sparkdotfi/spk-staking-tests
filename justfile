@_default:
    just --list

alias w := wake

wake:
    wake --config wake_model/wake.toml test wake_model -S ""
