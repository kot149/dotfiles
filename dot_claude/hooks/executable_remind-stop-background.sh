#!/usr/bin/env bash
# After a tool starts background work, remind Claude to stop it once its
# result is no longer needed, so late completion notifications do not keep
# triggering turns that only repeat the answer.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

case "$TOOL" in
    Agent)
        [[ "$(echo "$INPUT" | jq -r '.tool_response.status // ""')" == "completed" ]] && exit 0
        MSG="A background subagent is running. Once you have what you need from it, or have reached the conclusion yourself, stop it with TaskStop before giving the final answer instead of waiting for it."
        ;;
    Bash)
        [[ "$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')" == "true" ]] || exit 0
        MSG="A background shell is running. Stop it with TaskStop as soon as its output is no longer needed, and before giving the final answer."
        ;;
    Monitor)
        MSG="A monitor is running. Stop it with TaskStop as soon as the condition it watches no longer matters, and before giving the final answer."
        ;;
    ScheduleWakeup)
        [[ "$(echo "$INPUT" | jq -r '.tool_input.stop // false')" == "true" ]] && exit 0
        MSG="A wakeup is scheduled. When the task this loop serves is finished, end the loop with ScheduleWakeup(stop: true) instead of scheduling another wakeup."
        ;;
    CronCreate)
        MSG="A cron job is scheduled. Delete it with CronDelete once it is no longer needed."
        ;;
    *)
        exit 0
        ;;
esac

MSG="$MSG If a completion notification arrives after the answer and changes nothing, reply in one line without restating the answer."

jq -cn --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
