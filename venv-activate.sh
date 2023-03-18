#!/usr/bin/env bash

# This script places the user in the alice-core virtual environment,
# necessary to run unit tests or to interact directly with alice-core
# via an interactive Python shell.

# wrap in function to allow local variables, since this file will be source'd
function main() { 
    local quiet=0

    for arg in "$@"
    do
        case $arg in
            "-q"|"--quiet" )
               quiet=1
               ;;

            "-h"|"--help" )
               echo "venv-activate.sh:  Enter the Alice virtual environment"
               echo "Usage:"
               echo "   source venv-activate.sh"
               echo "or"
               echo "   . venv-activate.sh"
               echo ""
               echo "Options:"
               echo "   -q | --quiet    Don't show instructions."
               echo "   -h | --help    Show help."
               return 0
               ;;

            *)
               echo "ERROR:  Unrecognized option: $@"
               return 1
               ;;
       esac
    done

    if [[ "$0" == "$BASH_SOURCE" ]] ; then
        # Prevent running in script then exiting immediately
        echo "ERROR: Invoke with 'source venv-activate.sh' or '. venv-activate.sh'"
    else
        local SRC_DIR="$( builtin cd "$( dirname "${BASH_SOURCE}" )" ; pwd -P )"
        source ${SRC_DIR}/.venv/bin/activate
        
        # Provide an easier to find "alice-" prefixed command.
        unalias alice-venv-activate 2>/dev/null
        alias alice-venv-deactivate="deactivate && unalias alice-venv-deactivate 2>/dev/null && alias alice-venv-activate=\"source '${SRC_DIR}/venv-activate.sh'\""
        if [ $quiet -eq 0 ] ; then
            echo "Entering Alice virtual environment.  Run 'alice-venv-deactivate' to exit"
        fi
    fi
}

main $@
