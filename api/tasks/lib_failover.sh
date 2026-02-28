#!/bin/sh
# Helper for timeout-based failover handling used by workflow scripts.
# Usage: source this file and call `failover_check "$timeout" "$secs"`.

failover_check() {
    timeout="$1"
    secs="$2"
    # timeout must be a positive integer
    if [ -n "$timeout" ] && printf '%s' "$timeout" | grep -Eq '^[0-9]+$'; then
        if [ "$secs" -gt "$timeout" ]; then
            echo "timeout reached. ( $timeout ). Restarting ComfyUI..."
            cmd='Get-Process -Name python | Where-Object { ($_.PagedMemorySize64/1KB) -gt 10000000 } | ForEach-Object { Write-Output ("Killing {0} (pid {1}) PM(K)={2}" -f $_.ProcessName,$_.Id,[math]::Round($_.PagedMemorySize64/1KB)); Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }'
            encoded=$(printf '%s' "$cmd" | iconv -f utf-8 -t utf-16le | base64 -w0)
            powershell.exe -NoProfile -EncodedCommand "$encoded"
            echo "Waiting for restart."
            sleep 10
            echo "Aborting task after restart."
            return 1
        fi
    fi
    return 0
}

return 0
