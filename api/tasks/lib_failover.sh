#!/bin/sh
# Helper for timeout-based failover handling used by workflow scripts.
# Usage: source this file and call `failover_check "$timeout" "$secs"`.

failover_check() {
    timeout="$1"
    secs="$2"

    # If no explicit timeout provided, use a cached default. The first time
    # this function sees an empty timeout it will attempt to read
    # COMFYUI_CALLTIMEOUT from $CONFIGFILE and cache the result in
    # "_FAILOVER_DEFAULT_TIMEOUT". Subsequent calls use the cached value and
    # do not re-read the config file.
    if [ -z "$timeout" ]; then
        if [ -z "${_FAILOVER_DEFAULT_TIMEOUT+x}" ]; then
            if [ -n "$CONFIGFILE" ] && [ -f "$CONFIGFILE" ]; then
                _FAILOVER_DEFAULT_TIMEOUT=$(awk -F "=" '/COMFYUI_CALLTIMEOUT=/ {print $2}' "$CONFIGFILE" | head -n1)
            fi
            _FAILOVER_DEFAULT_TIMEOUT=${_FAILOVER_DEFAULT_TIMEOUT:-3600}
        fi
        timeout="${_FAILOVER_DEFAULT_TIMEOUT}"
    fi

    # If a comfyui_logwatch marker file exists and contains data, treat this
    # as an immediate crash signal and behave like a timeout was reached.
    marker_file="${COMFYUI_LOGWATCH_MARKER:-./user/default/comfyui_stereoscopic/.comfyui_logwatch_crash}"
    if [ -n "$marker_file" ] && [ -f "$marker_file" ] && [ -s "$marker_file" ]; then
        echo "ComfyUI crash marker detected at $marker_file. Restarting ComfyUI..."
        cmd='Get-Process -Name python | Where-Object { ($_.PagedMemorySize64/1KB) -gt 10000000 } | ForEach-Object { Write-Output ("Killing {0} (pid {1}) PM(K)={2}" -f $_.ProcessName,$_.Id,[math]::Round($_.PagedMemorySize64/1KB)); Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }'
        encoded=$(printf '%s' "$cmd" | iconv -f utf-8 -t utf-16le | base64 -w0)
        powershell.exe -NoProfile -EncodedCommand "$encoded"
        echo "Waiting for restart."
        sleep 10
        echo "Aborting task after restart."
        return 1
    fi

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
