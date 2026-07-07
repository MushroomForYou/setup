#!/bin/bash
# Logging functions with timestamps and colors

# Log levels
export LOG_LEVEL_DEBUG=0
export LOG_LEVEL_INFO=1
export LOG_LEVEL_WARN=2
export LOG_LEVEL_ERROR=3
export LOG_LEVEL_QUIET=4

# Default log level
export CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO

# Timestamp function
timestamp() {
    date '+%H:%M:%S'
}

# Logging functions
log() {
    if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_INFO ]; then
        echo -e "${GREEN}${ICON_OK}${NC} ${DIM}[$(timestamp)]${NC} $1"
    fi
}

warn() {
    if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_WARN ]; then
        echo -e "${YELLOW}${ICON_WARN}${NC} ${DIM}[$(timestamp)]${NC} ${YELLOW}$1${NC}"
    fi
}

err() {
    if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_ERROR ]; then
        echo -e "${RED}${ICON_ERR}${NC} ${DIM}[$(timestamp)]${NC} ${RED}$1${NC}" >&2
    fi
}

info() {
    if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_INFO ]; then
        echo -e "${CYAN}  ${ICON_ARROW}${NC} $1"
    fi
}

debug() {
    if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_DEBUG ]; then
        echo -e "${DIM}[DEBUG] [$(timestamp)]${NC} $1"
    fi
}

# Step indicator
step() {
    local num=$1
    local total=10
    local desc="$2"
    echo ""
    echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${WHITE}  STEP ${num}/${total}:${NC} ${CYAN}${desc}${NC}"
    echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Progress indicator
progress() {
    local current=$1
    local total=$2
    local desc="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    printf "\r${CYAN}[${GREEN}"
    printf "%0.s█" $(seq 1 $filled)
    printf "${NC}${DIM}"
    printf "%0.s░" $(seq 1 $empty)
    printf "${CYAN}]${NC} %3d%% %s" "$percent" "$desc"
    if [ $current -eq $total ]; then
        echo ""
    fi
}

# Box drawing
draw_box() {
    local title="$1"
    local width=56
    local padding=$(( (width - ${#title} - 2) / 2 ))

    echo -e "${GREEN}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
    echo -e "${GREEN}║${NC}$(printf ' %.0s' $(seq 1 $padding))${BOLD}${WHITE}$title${NC}$(printf ' %.0s' $(seq 1 $((width - padding - ${#title} - 2))))${GREEN}║${NC}"
    echo -e "${GREEN}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
}

draw_line() {
    local char="${1:-─}"
    local width="${2:-56}"
    echo -e "${GREEN}$(printf '%s%.0s' "$char" $(seq 1 $width))${NC}"
}
