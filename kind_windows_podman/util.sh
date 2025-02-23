# util.sh

# bash utility functions to source into script

if [[ $(uname) != CYGWIN_NT-* ]]; then
  echo >&2 "This script only runs on Cygwin on Windows"
  exit 1
fi

shopt -s expand_aliases
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias kubectl="kubecolor --force-colors"

# for debug trap behavior to control execution of next command
shopt -s extdebug

shopt -s extglob

# enable history without special characters like bang ! and without saving commands in history file
unset HISTFILE histchars
set -o history

function confirm_step_list_steps {
  sed -En 's/^ *confirm_step +"(.*)" +(\S+)/\2: \1/p' ${BASH_SOURCE[1]} |
  awk '
    BEGIN {
      delete undo_steps
      print "Normal mode steps:"
    }
    /^undo_/ {
      undo_steps[length(undo_steps)] = $0
      next
    }
    { print } 
    END {
      if(length(undo_steps) == 0) {
        exit
      }
      printf "\n"
      print "Undo mode steps:"
      for(i = 0; i < length(undo_steps); ++i) {
        printf "%s\n", undo_steps[i]
      }
    }
  '
}

declare -A confirm_step_config=(
  interactive=true
)

declare confirm_step_label
declare confirm_step_msg
declare -a confirm_step_cmds_queue
declare confirm_step_cmds_queue_head

# replace plain bash variable references with values in expression
# usage: confirm_step_expandvars filled_expression "$expression_with_variables"
# expanded expression is returned in arg 1

function confirm_step_expandvars {
  local -n expanded_ref=$1
  shift
  local s=$*

# match and remove command substitution wrapper and assignment to variable
# cmdout=$(curl $url) becomes curl $url
  [[ $s =~ ^[$' \t']*[_[:alnum:]]+=\$\((.*)\) ]] && s=${BASH_REMATCH[1]}

# regex match examples
# curl --output-dir $downloaddir -LO https://get.helm.sh/$helm_zipfile
# unzip -j -o -d $toolsdir ${downloaddir}/${helm_zipfile} windows-amd64/helm.exe
# regex has 4 groups /(no variables) ( ($varname) | (${varname}) )/ but we only use group 1 and 2
  local pat='^([^$]*)((\$[a-zA-Z_0-9]+)|(\$\{[a-zA-Z_0-9]+\}))'

# progressive regex matching loop over s
  for ((;;)); do
    [[ $s =~ $pat ]] || break
# m1 is initial substring without variables group 1
    local m1=${BASH_REMATCH[1]}
# m2 is matched variable group 2, same as group 3 $varname or group 4 ${varname}
    local m2=${BASH_REMATCH[2]}
# strip $ or ${} from m2 to get variable name then use indirection to get value, another simpler but riskier way is eval local var=$m2
    [[ ${m2:1:1} == "{" ]] && m2=${m2:2:${#m2} - 3} || m2=${m2:1}
    local val=${!m2}
# replace variable with its value
    expanded_ref+="$m1$val"
# strip matched portion to continue matching remaining string
    s=${s:${#BASH_REMATCH[0]}}
  done
  expanded_ref+=$s
}

# runs immediately before command that follows call to confirm_step
# contains interactive prompt for user to confirm next command

function confirm_step_trap {
  local cmdsblock="$(history 1 | sed -E '1s/^ *[0-9]+ +//')"

# unset debug trap
  (( confirm_step_multicmds_idx + 1 == confirm_step_multicmds_count )) && trap - debug
  local next_cmd
# return confirmation value from first command in multicommand step
  if (( confirm_step_multicmds_idx++ > 0 )); then
    confirm_step_expandvars next_cmd "$BASH_COMMAND"
    if (( confirm_step_multicmds_rv == 0 )); then
      echo "$next_cmd"
    else
      echo "Skip Step $confirm_step_label command $confirm_step_multicmds_idx: $next_cmd"
    fi
    return $confirm_step_multicmds_rv
  fi

  local next_cmd_with_vars

# get next command from commands queue if not empty or directly from history
  if (( confirm_step_cmds_queue_head < ${#confirm_step_cmds_queue[*]} )); then
    next_cmd_with_vars=${confirm_step_cmds_queue[confirm_step_cmds_queue_head]}
    let ++confirm_step_cmds_queue_head
    if (( confirm_step_cmds_queue_head == ${#confirm_step_cmds_queue[*]} )); then
      confirm_step_cmds_queue=()
    fi
  else
# use history instead of BASH_COMMAND to get complete pipelines and unexpanded aliases
    next_cmd_with_vars="$(history 1 | sed -E '1s/^ *[0-9]+ +//')"
  fi

  confirm_step_expandvars next_cmd "$next_cmd_with_vars"

# print message and next command if noninteractive
  if ! ${confirm_step_config[interactive]}; then
    echo "Step $confirm_step_label: $confirm_step_msg"
    echo "$next_cmd"
    confirm_step_multicmds_rv=0
    return
  fi

  if [[ -n $jump_step_label ]]; then
    if [[ $jump_step_label != $confirm_step_label ]]; then
      echo "Step $confirm_step_label: $confirm_step_msg"
      if (( confirm_step_multicmds_count > 1 )); then
        echo "Skip Step $confirm_step_label command 1: $next_cmd"
      else
        echo "Skip Step $confirm_step_label: $next_cmd"
      fi
      confirm_step_multicmds_rv=1
      return 1
    else
      jump_step_label=
    fi
  fi

# ask to run next command
# case-insensitive response is single character
# y: yes, run next command, space and newline act as y
# q: quit, exit script immediately
# j: jump to step entered after followup prompt, skip all steps in between
# r: run all following steps non-interactively
# n: no, skip next command, any other character acts as n

  read -N1 -p "Step $confirm_step_label: $confirm_step_msg? [y/n/q/j/r] " <> /dev/tty 1>&0

# process response
# no extra newline if response is newline itself
  [[ $REPLY == $'\n' ]] || echo

# q to quit program
  [[ $REPLY == [qQ] ]] && exit

# r to print and run all remaining steps without prompting
  if [[ $REPLY == [rR] ]]; then
    confirm_step_config[interactive]=false
    echo "$next_cmd"
    confirm_step_multicmds_rv=0
    return
  fi

# y to run next command, space and newline act as y
  if [[ $REPLY = [yY$' \n'] ]]; then
    echo "$next_cmd"
    confirm_step_multicmds_rv=0
    return
  fi

# j to jump to step with label entered at second prompt, skipping all steps in between
  if [[ $REPLY == [jJ] ]]; then
    IFS= read -r -p "Jump to Step? " jump_step_label <> /dev/tty 1>&0
# trim whitespace around response
    jump_step_label=${jump_step_label##*( )} 
    jump_step_label=${jump_step_label%%*( )} 
  fi

# n to skip next command, all other characters act as n
  if (( confirm_step_multicmds_count > 1 )); then
    echo "Skip Step $confirm_step_label command 1: $next_cmd"
  else
    echo "Skip Step $confirm_step_label: $next_cmd"
  fi
  confirm_step_multicmds_rv=1
  return 1
}

# a step is the next command to confirm with message
# step has optional label that can be any string
# arg 1 is step message
# optional arg 2 is step label
# optional arg 3 is number of commands in multicommand step, default is 1
# example:
# script contains the two line:
# confirm_step "Create Podman machine" podman_1
# podman machine init
# here step command is "podman machine init", step message is "Create Podman machine", step label is podman_1
# user sees:
# Step podman_1: Create Podman machine? [y/n/q/j/r]
# If user types y, "Step podman_1: podman machine init" is printed and command runs
# If user types n, "Skip Step podman_1: podman machine init" is printed and command does not run
# If user types q, program exits, nothing is printed and command does not run
# If user types j, secondary prompt appears "Jump to Step?". Say user types podman_9. Then "Skip Step podman_1: podman machine init" is printed and command does not run. All following steps until step podman_9 are skipped with a skip message. Normal prompting resumes at step podman_9.
# If user types r, all following steps are printed and run till termination
# possible r mode enhancement could be to track exit status of step command and switch to interactive mode on first error
# limitations:
# cannot be used inside function
# can be used inside control-flow blocks like if-then-fi, while-do-done, braces {} etc if confirm_step_enter_block is called just before block
function confirm_step {
  confirm_step_msg=$1
  confirm_step_label=$2

# trap runs for idx >= 0 && idx < count
# trap cleared for idx == count
# trap return value saved for idx 0
# trap returns saved return value for idx > 0 && idx < count
  confirm_step_multicmds_count=${3:-1}
  confirm_step_multicmds_idx=0
  confirm_step_multicmds_rv=

# check if commands queue should be filled from function or non-function block of commands like if-then-fi
  if (( ${#confirm_step_cmds_queue[*]} == 0 )); then
    if ((${#FUNCNAME[*]} > 2)); then
# detect confirm_step called from inside function because function array size is at least 3 like [confirm_step, undo, main]
      local funcblock=$(declare -f ${FUNCNAME[1]})
      confirm_step_extract_cmds "$funcblock"
    else
      local nonfuncblock="$(history 1 | sed -E '1s/^ *[0-9]+ +//')"
      if [[ $nonfuncblock =~ [^[:space:]]+.*[[:\<:]]confirm_step[[:\>:]] ]]; then
# detect confirm_step called from inside non-function block of commands because history entry has non-whitespace before confirm_step call
        confirm_step_extract_cmds "$nonfuncblock"
      fi
    fi
  fi

# set debug trap to confirm next command
  trap confirm_step_trap debug
}

# fill confirm_step_cmds_queue with step commands parsed out of block of commands passed as argument
# block of commands could be function, if-then-fi or anything because this just matches anything terminated by semicolon and extracts the command that immediately follows confirm_step command
function confirm_step_extract_cmds {

  local cmdsblock=$1

  confirm_step_cmds_queue=()
  confirm_step_cmds_queue_head=0

  local save_cmd=false
  local s=$cmdsblock

# keep matching commands with semicolon terminator
  for ((;;)); do
    [[ $s =~ [[:space:]]*([^;]+)\; ]] || break
# strip matched portion to continue matching remaining string
    s=${s:${#BASH_REMATCH[0]}}

    local cmd=${BASH_REMATCH[1]}
    if $save_cmd; then
# clear flag and add command to commands queue
      confirm_step_cmds_queue+=("$cmd")
      save_cmd=false
    elif [[ $cmd =~ [[:\<:]]confirm_step[[:\>:]] ]]; then
# set flag to add command that follows confirm_step to commands queue
      save_cmd=true
    fi
  done
}

function confirm_step_usage {
  echo "This script runs interactive steps. Each step is a significant command that must be confirmed or skipped."
  echo "A label and message is printed for each step"
  echo "The response is a single case-insensitive character - y/n/q/j/r"
  echo "y: yes, run next command (space and newline act as y)"
  echo "q: quit, exit script immediately"
  echo "j: jump to step with label entered after prompt, skip all steps in between"
  echo "r: run all following steps non-interactively"
  echo "n: no, do not run next command (all other characters act as n)"
}

