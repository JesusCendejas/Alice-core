#!/usr/bin/env bash



SOURCE="${BASH_SOURCE[0]}"

script=${0}
script=${script##*/}
cd -P "$( dirname "$SOURCE" )"

function help() {
    echo "${script}:  Alice service stopper"
    echo "usage: ${script} [service]"
    echo
    echo "Service:"
    echo "  all       ends core services: bus, audio, skills, voice"
    echo "  (none)    same as \"all\""
    echo "  bus       stop the Alice messagebus service"
    echo "  audio     stop the audio playback service"
    echo "  skills    stop the skill service"
    echo "  voice     stop voice capture service"
    echo "  enclosure stop enclosure (hardware/gui interface) service"
    echo
    echo "Examples:"
    echo "  ${script}"
    echo "  ${script} audio"

    exit 0
}

function process-running() {
    if [[ $( pgrep -f "python3 (.*)-m alice.*${1}" ) ]] ; then
        return 0
    else
        return 1
    fi
}

function end-process() {
    if process-running $1 ; then
        # Find the process by name, only returning the oldest if it has children
        pid=$( pgrep -o -f "python3 (.*)-m alice.*${1}" )
        echo -n "Stopping $1 (${pid})..."
        kill -SIGINT ${pid}

        # Wait up to 5 seconds (50 * 0.1) for process to stop
        c=1
        while [ $c -le 50 ] ; do
            if process-running $1 ; then
                sleep 0.1
                (( c++ ))
            else
                c=999   # end loop
            fi
        done

        if process-running $1 ; then
            echo "failed to stop."
            pid=$( pgrep -o -f "python3 (.*)-m alice.*${1}" )            
            echo -n "  Killing $1 (${pid})..."
            kill -9 ${pid}
            echo "killed."
            result=120
        else
            echo "stopped."
            if [ $result -eq 0 ] ; then
                result=100
            fi
        fi
    fi
}


result=0  # default, no change


OPT=$1
shift

case ${OPT} in
    "all")
        ;&
    "")
        echo "Stopping all alice-core services"
        end-process skills
        end-process audio
        end-process speech
        end-process enclosure
        end-process messagebus.service
        ;;
    "bus")
        end-process messagebus.service
        ;;
    "audio")
        end-process audio
        ;;
    "skills")
        end-process skills
        ;;
    "voice")
        end-process speech
        ;;
    "enclosure")
        end-process enclosure
        ;;

    *)
        help
        ;;
esac

# Exit codes:
#     0   if nothing changed (e.g. --help or no process was running)
#     100 at least one process was stopped
#     120 if any process had to be killed
exit $result