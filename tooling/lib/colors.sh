#!/usr/bin/env bash
#
# colors.sh - Brand color scheme and formatting utilities
#
# Brand palette:
#   BRAND (aqua)  — primary headings, prompts, identity
#   GOOD (green)  — success, pass, completion
#   BAD (red)     — errors, failures, warnings
#   CYAN          — metadata, details, alternate highlight
#   YELLOW        — warnings, interactive prompts, alternate highlight
#   DIM           — secondary text, separators

# ─── Brand colors (256-color for richer aqua) ──────────────────────
BRAND='\033[38;5;51m'     # Bright aqua (#00FFFF)
BRAND_BOLD='\033[1;38;5;51m'
BAD='\033[0;31m'
BAD_BOLD='\033[1;31m'
GOOD='\033[0;32m'
GOOD_BOLD='\033[1;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
DIM='\033[2m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
NC='\033[0m'

# ─── Repeat a string N times ─────────────────────────────────────
# Works correctly with multi-byte UTF-8 characters like ─ ═ etc.
_repeat() {
    local str="$1" n="$2" result="" j
    for ((j=0; j<n; j++)); do result+="$str"; done
    printf '%s' "$result"
}

# ─── Box-drawing header ────────────────────────────────────────────
# Usage: print_box_header "Title text" [width]
print_box_header() {
    local title="$1"
    local width="${2:-50}"
    local inner=$(( width - 4 ))
    local pad_total=$(( inner - ${#title} ))
    local pad_left=$(( pad_total / 2 ))
    local pad_right=$(( pad_total - pad_left ))

    echo ""
    echo -e "${BRAND}  ╔$(_repeat '═' $inner)╗${NC}"
    echo -e "${BRAND}  ║$(printf '%*s' $pad_left '')${BRAND_BOLD}${title}${BRAND}$(printf '%*s' $pad_right '')║${NC}"
    echo -e "${BRAND}  ╚$(_repeat '═' $inner)╝${NC}"
    echo ""
}

# ─── Section header with divider line ──────────────────────────────
# Usage: print_section "Section Name"
print_section() {
    local title="$1"
    echo ""
    echo -e "  ${BRAND_BOLD}${title}${NC}"
    echo -e "  ${DIM}$(_repeat '─' ${#title})${NC}"
}

# ─── Status badge ──────────────────────────────────────────────────
# Usage: status_badge "queued"  →  colored status string
status_badge() {
    local status="$1"
    case "$status" in
        queued)    echo -e "${GOOD}●${NC} ${GOOD}queued${NC}" ;;
        active)    echo -e "${CYAN}●${NC} ${CYAN}active${NC}" ;;
        completed) echo -e "${BRAND}●${NC} ${BRAND}completed${NC}" ;;
        failed)    echo -e "${BAD}●${NC} ${BAD}failed${NC}" ;;
        stopped)   echo -e "${YELLOW}●${NC} ${YELLOW}stopped${NC}" ;;
        *)         echo -e "${DIM}●${NC} ${DIM}${status}${NC}" ;;
    esac
}

# ─── Key-value display ─────────────────────────────────────────────
# Usage: print_kv "Key" "Value" [key_width]
print_kv() {
    local key="$1"
    local value="$2"
    local width="${3:-16}"
    printf "  ${DIM}%-${width}s${NC} %s\n" "${key}:" "$value"
}

# ─── Table rendering ──────────────────────────────────────────────
#
# Column widths are set by TABLE_WIDTHS array (caller must define):
#   TABLE_WIDTHS=(19 11 9 21 40 4)
#
# Optional: TABLE_INDENT controls left indent (default: "  ")

TABLE_WIDTHS=()
TABLE_INDENT="  "

# Pad or truncate a value to exactly $width visible characters
_fmt_col() {
    local val="$1" w="$2"
    if [[ ${#val} -gt $w ]]; then
        val="${val:0:$(( w - 1 ))}"  # leave 1 char for spacing
    fi
    printf "%-${w}s" "$val"
}

table_header() {
    local cols=("$@")
    local line="" sep=""
    local i

    for i in "${!cols[@]}"; do
        local w="${TABLE_WIDTHS[$i]:-20}"
        line+="$(_fmt_col "${cols[$i]}" "$w")"
        sep+="$(_repeat '─' $(( w - 1 ))) "
    done

    echo -e "${TABLE_INDENT}${DIM}${line}${NC}"
    echo -e "${TABLE_INDENT}${DIM}${sep}${NC}"
}

table_row() {
    local cols=("$@")
    local line=""
    local i

    for i in "${!cols[@]}"; do
        local w="${TABLE_WIDTHS[$i]:-20}"
        line+="$(_fmt_col "${cols[$i]}" "$w")"
    done

    printf '%s%s\n' "${TABLE_INDENT}" "${line}"
}

# Status-colored row: the STATUS column (index 1) gets colored
table_row_status() {
    local cols=("$@")
    local line=""
    local i

    # Determine color from the status value (second column)
    local status="${cols[1]}"
    local scolor=""
    case "$status" in
        queued)    scolor="$GOOD" ;;
        active)    scolor="$CYAN" ;;
        completed) scolor="$BRAND" ;;
        failed)    scolor="$BAD" ;;
        stopped)   scolor="$YELLOW" ;;
        *)         scolor="$DIM" ;;
    esac

    for i in "${!cols[@]}"; do
        local w="${TABLE_WIDTHS[$i]:-20}"
        local cell
        cell="$(_fmt_col "${cols[$i]}" "$w")"
        if [[ $i -eq 1 ]]; then
            line+="$(printf "${scolor}%s${NC}" "$cell")"
        else
            line+="$cell"
        fi
    done

    echo -e "${TABLE_INDENT}${line}"
}

# Numbered row for select view — prepends "  N) " before the row
table_row_numbered() {
    local num="$1"
    shift
    local cols=("$@")
    local line=""
    local i

    local status="${cols[1]}"
    local scolor=""
    case "$status" in
        queued)    scolor="$GOOD" ;;
        active)    scolor="$CYAN" ;;
        completed) scolor="$BRAND" ;;
        failed)    scolor="$BAD" ;;
        stopped)   scolor="$YELLOW" ;;
        *)         scolor="$DIM" ;;
    esac

    for i in "${!cols[@]}"; do
        local w="${TABLE_WIDTHS[$i]:-20}"
        local cell
        cell="$(_fmt_col "${cols[$i]}" "$w")"
        if [[ $i -eq 1 ]]; then
            line+="$(printf "${scolor}%s${NC}" "$cell")"
        else
            line+="$cell"
        fi
    done

    printf "  ${CYAN}%3d)${NC} " "$num"
    echo -e "${line}"
}

table_end() {
    echo ""
}

# ─── Prompt helpers ────────────────────────────────────────────────
# Usage: prompt_choice "Select CLI" "claude" "copilot"
#        Returns the selected value via $REPLY
prompt_choice() {
    local title="$1"
    shift
    local options=("$@")
    local i

    echo -e "  ${BRAND}${title}${NC}"
    echo ""
    for i in "${!options[@]}"; do
        local num=$(( i + 1 ))
        echo -e "    ${CYAN}${num})${NC} ${options[$i]}"
    done
    echo ""

    while true; do
        read -p "    Choice [1]: " choice
        choice="${choice:-1}"

        # Match by number
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]]; then
            REPLY="${options[$(( choice - 1 ))]}"
            return
        fi

        # Match by option text (case-insensitive)
        for i in "${!options[@]}"; do
            if [[ "${options[$i],,}" == "${choice,,}" ]]; then
                REPLY="${options[$i]}"
                return
            fi
        done

        echo -e "    ${BAD}Invalid choice '${choice}'. Enter a number (1-${#options[@]}) or option name.${NC}"
    done
}

# Inline confirmation
# Usage: confirm "Do something?" && echo "yes"
confirm() {
    local msg="$1"
    read -p "  ${msg} [y/N]: " answer
    [[ "${answer:-n}" =~ ^[Yy]$ ]]
}

# ─── Log-style messages ───────────────────────────────────────────
log_info()    { echo -e "  ${BRAND}▸${NC} $*"; }
log_good()    { echo -e "  ${GOOD}✓${NC} $*"; }
log_bad()     { echo -e "  ${BAD}✗${NC} $*"; }
log_warn()    { echo -e "  ${YELLOW}!${NC} $*"; }
log_dim()     { echo -e "  ${DIM}$*${NC}"; }
