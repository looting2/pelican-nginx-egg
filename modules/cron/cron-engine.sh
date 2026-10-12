#!/bin/bash
# Production Cron-Engine for containers
CRON_CONFIG_FILE="${CRON_CONFIG_FILE:-/home/container/crontab}"
CRON_LOG_FILE="${CRON_LOG_FILE:-/home/container/logs/cron.log}"

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$CRON_LOG_FILE"
}

# Validate command doesn't contain dangerous patterns
validate_command() {
  local cmd="$1"
  # Block commands that could escape the container context
  if [[ "$cmd" =~ (^|[[:space:]])(rm[[:space:]]+-rf[[:space:]]+/[[:space:]]*$|dd[[:space:]]+if=|mkfs\.|:\(\)\{) ]]; then
    log_message "BLOCKED dangerous command pattern: $cmd"
    return 1
  fi
  return 0
}

# Return 0 for a match, 1 for no match, or 2 for an invalid field.
match_field() {
  local field="$1" value="$2" minimum="$3" maximum="$4"
  local item base step start end candidate matched=1
  local -a items
  [[ "$field" =~ ^[0-9*,/-]+$ ]] || return 2
  [[ -n "$field" && "$field" != ,* && "$field" != *, && "$field" != *,,* ]] || return 2
  IFS=',' read -r -a items <<< "$field"
  for item in "${items[@]}"; do
    # Validate before using any user input in Bash arithmetic.
    [[ "$item" =~ ^(\*|[0-9]{1,2}(-[0-9]{1,2})?)(/[0-9]{1,2})?$ ]] || return 2
    base="${item%%/*}"
    step=1
    if [[ "$item" == */* ]]; then
      step="${item##*/}"
      step=$((10#$step))
      ((step > 0)) || return 2
    fi
    if [[ "$base" == "*" ]]; then
      start=$minimum
      end=$maximum
    elif [[ "$base" == *-* ]]; then
      start="${base%-*}"
      end="${base#*-}"
      start=$((10#$start))
      end=$((10#$end))
    else
      start=$((10#$base))
      end=$start
      [[ "$item" == */* ]] && end=$maximum
    fi
    ((start >= minimum && end <= maximum && start <= end)) || return 2
    for ((candidate=start; candidate<=end; candidate+=step)); do
      # Both 0 and 7 denote Sunday in the weekday field.
      if ((candidate == value || (maximum == 7 && candidate == 7 && value == 0))); then
        matched=0
      fi
    done
  done
  return "$matched"
}

execute_if_match() {
  local minute="$1" hour="$2" day="$3" month="$4" weekday="$5" command="$6"
  local curr_min curr_hour curr_day curr_month curr_weekday
  read -r curr_min curr_hour curr_day curr_month curr_weekday < <(date '+%M %H %d %m %w')
  curr_min=$((10#$curr_min))
  curr_hour=$((10#$curr_hour))
  curr_day=$((10#$curr_day))
  curr_month=$((10#$curr_month))
  local -a fields=("$minute" "$hour" "$day" "$month" "$weekday")
  local -a values=("$curr_min" "$curr_hour" "$curr_day" "$curr_month" "$curr_weekday")
  local -a minima=(0 0 1 1 0) maxima=(59 23 31 12 7) matches
  local index status
  for index in 0 1 2 3 4; do
    if match_field "${fields[index]}" "${values[index]}" "${minima[index]}" "${maxima[index]}"; then
      status=0
    else
      status=$?
    fi
    if ((status == 2)); then
      log_message "ERROR: Invalid cron field: ${fields[index]}"
      return 2
    fi
    matches[index]=$status
  done
  ((matches[0] == 0 && matches[1] == 0 && matches[3] == 0)) || return 0
  # Cron uses OR for two restricted day fields, AND if either starts with *.
  if [[ "$day" == \** || "$weekday" == \** ]]; then
    ((matches[2] == 0 && matches[4] == 0)) || return 0
  else
    ((matches[2] == 0 || matches[4] == 0)) || return 0
  fi

  # Validate command before execution
  if ! validate_command "$command"; then
    return 1
  fi

  # Execute command using bash -c for controlled execution
  log_message "Executing: $command"
  /bin/bash -c "$command" >> "$CRON_LOG_FILE" 2>&1
}

main() {
  log_message "Cron engine started (PID: $$)"
  local line minute hour day month weekday command
  while true; do
    if [[ -f "$CRON_CONFIG_FILE" ]]; then
      # Read file safely without command expansion
      while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        read -r minute hour day month weekday command <<< "$line"
        [[ -z "$command" ]] && {
          log_message "ERROR: Invalid cron line: $line"
          continue
        }

        execute_if_match "$minute" "$hour" "$day" "$month" "$weekday" "$command"
      done < "$CRON_CONFIG_FILE"
    fi

    # Sleep until next minute
    sleep $((60 - 10#$(date '+%S')))
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi