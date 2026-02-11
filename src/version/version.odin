package version

// Build metadata (set via -define at compile time)
VERSION :: #config(VERSION, "dev")
GIT_COMMIT :: #config(GIT_COMMIT, "unknown")
BUILD_TIME :: #config(BUILD_TIME, "unknown")
REPOSITORY :: "github.com/xDarkicex/zephyr"

// ASCII art logo
LOGO :: `    ███████╗███████╗██████╗ ██╗  ██╗██╗   ██╗██████╗ 
    ╚══███╔╝██╔════╝██╔══██╗██║  ██║╚██╗ ██╔╝██╔══██╗
      ███╔╝ █████╗  ██████╔╝███████║ ╚████╔╝ ██████╔╝
     ███╔╝  ██╔══╝  ██╔═══╝ ██╔══██║  ╚██╔╝  ██╔══██╗
    ███████╗███████╗██║     ██║  ██║   ██║   ██║  ██║
    ╚══════╝╚══════╝╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝`

// Color constants
CYAN  :: "\x1b[36m"
BOLD  :: "\x1b[1m"
RESET :: "\x1b[0m"
