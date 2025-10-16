#!/bin/bash
#
# Mock system tools (free, iostat, ps, etc.) for testing
#

COMMAND="$1"
shift

case "$COMMAND" in
    free)
        if [[ "$*" == *"-g"* ]]; then
            cat << 'EOF'
              total        used        free      shared  buff/cache   available
Mem:            256          80         120           0          56         176
Swap:             8           0           8
EOF
        elif [[ "$*" == *"-h"* ]]; then
            cat << 'EOF'
              total        used        free      shared  buff/cache   available
Mem:           256G         80G        120G          0B         56G        176G
Swap:            8G          0B          8G
EOF
        fi
        ;;

    nproc)
        echo "28"
        ;;

    uptime)
        echo " 10:30:45 up 5 days, 3:20,  2 users,  load average: 2.15, 1.89, 1.67"
        ;;

    ps)
        if [[ "$*" == *"mysqld"* ]]; then
            cat << 'EOF'
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
mysql     1234  5.2 31.2 82944000 82944000 ?   Ssl  Jan01 150:30 /usr/sbin/mysqld
EOF
        fi
        ;;

    iostat)
        if [[ "$*" == *"-x"* ]]; then
            cat << 'EOF'
Device            r/s     w/s     rkB/s     wkB/s   rrqm/s   wrqm/s  %rrqm  %wrqm r_await w_await aqu-sz rareq-sz wareq-sz  svctm  %util
sda             50.00  100.00   1024.00   2048.00     5.00    10.00  10.00  10.00    2.00    5.00   0.50    20.48    20.48   1.00  15.0
EOF
        fi
        ;;

    du)
        if [[ "$*" == *"-h"* ]]; then
            echo "10M"
        else
            echo "10240"
        fi
        ;;

    realpath)
        # Just echo the input path
        echo "$1"
        ;;

    *)
        echo "Mock: Unknown command $COMMAND" >&2
        exit 1
        ;;
esac

exit 0
