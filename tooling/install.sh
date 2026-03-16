#!/usr/bin/env bash
#
# install.sh - Install the patchboard shell utility
#
# Creates a symlink in ~/.local/bin (or /usr/local/bin) and sets up
# bash completions so you can run `patchboard` from anywhere.
#
# Usage:
#   .patchboard/tooling/install.sh           # Install to ~/.local/bin
#   .patchboard/tooling/install.sh --global  # Install to /usr/local/bin
#   .patchboard/tooling/install.sh --remove  # Uninstall

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHBOARD_SCRIPT="${SCRIPT_DIR}/patchboard.bash"
COMPLETIONS_SCRIPT="${SCRIPT_DIR}/patchboard-completions.bash"

# Brand colors
BRAND='\033[38;5;51m'
BRAND_BOLD='\033[1;38;5;51m'
GOOD='\033[0;32m'
BAD='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

log_good()  { echo -e "  ${GOOD}✓${NC} $*"; }
log_bad()   { echo -e "  ${BAD}✗${NC} $*"; }
log_info()  { echo -e "  ${BRAND}▸${NC} $*"; }
log_dim()   { echo -e "  ${DIM}$*${NC}"; }

print_header() {
    local title="Patchboard CLI Installer"
    local inner=42
    local pad_total=$(( inner - ${#title} ))
    local pad_left=$(( pad_total / 2 ))
    local pad_right=$(( pad_total - pad_left ))
    local i

    _repeat() { local s="$1" n="$2" r="" j; for ((j=0;j<n;j++)); do r+="$s"; done; printf '%s' "$r"; }

    echo ""
    echo -e "${BRAND}  ╔$(_repeat '═' $inner)╗${NC}"
    echo -e "${BRAND}  ║$(printf '%*s' $pad_left '')${BRAND_BOLD}${title}${BRAND}$(printf '%*s' $pad_right '')║${NC}"
    echo -e "${BRAND}  ╚$(_repeat '═' $inner)╝${NC}"
    echo ""
}

# Determine install directory
get_install_dir() {
    local global="${1:-false}"
    if [[ "$global" == "true" ]]; then
        echo "/usr/local/bin"
    else
        echo "${HOME}/.local/bin"
    fi
}

# Detect shell config file
get_shell_rc() {
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
        echo "${HOME}/.zshrc"
    else
        echo "${HOME}/.bashrc"
    fi
}

install_patchboard() {
    local global="${1:-false}"
    local install_dir
    install_dir=$(get_install_dir "$global")
    local link_path="${install_dir}/patchboard"
    local shell_rc
    shell_rc=$(get_shell_rc)

    print_header

    # Ensure script is executable
    chmod +x "$PATCHBOARD_SCRIPT"

    # Create install directory
    if [[ ! -d "$install_dir" ]]; then
        log_info "Creating ${install_dir}..."
        mkdir -p "$install_dir"
    fi

    # Create symlink
    if [[ -L "$link_path" ]]; then
        local current_target
        current_target=$(readlink -f "$link_path")
        if [[ "$current_target" == "$(readlink -f "$PATCHBOARD_SCRIPT")" ]]; then
            log_good "Symlink already up to date: ${link_path}"
        else
            log_info "Updating symlink: ${link_path}"
            ln -sf "$PATCHBOARD_SCRIPT" "$link_path"
            log_good "Symlink updated"
        fi
    elif [[ -e "$link_path" ]]; then
        log_bad "${link_path} exists but is not a symlink"
        echo -e "  ${DIM}Remove it manually and re-run install${NC}"
        return 1
    else
        log_info "Creating symlink: ${link_path} → ${PATCHBOARD_SCRIPT}"
        ln -sf "$PATCHBOARD_SCRIPT" "$link_path"
        log_good "Symlink created"
    fi

    # Ensure install_dir is in PATH
    if [[ ":${PATH}:" != *":${install_dir}:"* ]]; then
        log_info "Adding ${install_dir} to PATH in ${shell_rc}..."
        echo "" >> "$shell_rc"
        echo "# Patchboard CLI" >> "$shell_rc"
        echo "export PATH=\"${install_dir}:\$PATH\"" >> "$shell_rc"
        log_good "PATH updated in ${shell_rc}"
    else
        log_good "${install_dir} already in PATH"
    fi

    # Install completions
    local completions_marker="# Patchboard completions"
    if grep -q "$completions_marker" "$shell_rc" 2>/dev/null; then
        log_good "Completions already configured in ${shell_rc}"
    else
        log_info "Adding completions to ${shell_rc}..."
        echo "" >> "$shell_rc"
        echo "${completions_marker}" >> "$shell_rc"
        echo "[ -f \"${COMPLETIONS_SCRIPT}\" ] && source \"${COMPLETIONS_SCRIPT}\"" >> "$shell_rc"
        log_good "Completions added"
    fi

    echo ""
    echo -e "  ${BRAND_BOLD}Installation complete!${NC}"
    echo ""
    echo -e "  ${DIM}Reload your shell or run:${NC}"
    echo -e "    ${CYAN}source ${shell_rc}${NC}"
    echo ""
    echo -e "  ${DIM}Then try:${NC}"
    echo -e "    ${CYAN}patchboard version${NC}"
    echo -e "    ${CYAN}patchboard healthcheck${NC}"
    echo -e "    ${CYAN}patchboard help${NC}"
    echo ""
}

uninstall_patchboard() {
    local shell_rc
    shell_rc=$(get_shell_rc)

    print_header
    log_info "Uninstalling patchboard..."

    # Remove symlinks
    for dir in "${HOME}/.local/bin" "/usr/local/bin"; do
        local link="${dir}/patchboard"
        if [[ -L "$link" ]]; then
            rm -f "$link"
            log_good "Removed ${link}"
        fi
    done

    # Remove completions from shell rc (leave PATH line — user may have other tools there)
    if [[ -f "$shell_rc" ]]; then
        local tmp="${shell_rc}.patchboard-tmp"
        grep -v "Patchboard completions\|patchboard-completions.bash" "$shell_rc" > "$tmp" || true
        mv "$tmp" "$shell_rc"
        log_good "Removed completions from ${shell_rc}"
    fi

    echo ""
    log_good "Uninstalled. Reload your shell to apply."
    echo ""
}

# ─── Main ──────────────────────────────────────────────────────────

case "${1:-}" in
    --global|-g)
        install_patchboard true
        ;;
    --remove|--uninstall|-r)
        uninstall_patchboard
        ;;
    --help|-h)
        echo "Usage: install.sh [--global] [--remove]"
        echo ""
        echo "  (default)    Install to ~/.local/bin"
        echo "  --global     Install to /usr/local/bin"
        echo "  --remove     Uninstall"
        ;;
    *)
        install_patchboard false
        ;;
esac
