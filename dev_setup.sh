#!/usr/bin/env bash

# Set a default locale to handle output from commands reliably
export LANG=C.UTF-8
export LANGUAGE=en

# exit on any error
set -Ee

ROOT_DIRNAME=$(dirname "$0")
cd "$ROOT_DIRNAME"
TOP=$(pwd -L)

function clean_alice_files() {
    echo '
This will completely remove any files installed by alice (including pairing
information). 

NOTE: This will not remove Mimic (if you chose to compile it), or other files
generated within the alice-core directory.

Do you wish to continue? (y/n)'
    while true; do
        read -rN1 -s key
        case $key in
        [Yy])
            sudo rm -rf /var/log/alice
            rm -f /var/tmp/alice_web_cache.json
            rm -rf "${TMPDIR:-/tmp}/alice"
            rm -rf "$HOME/.alice"
            rm -f "skills"  # The Skills directory symlink
            sudo rm -rf "/opt/alice"
            exit 0
            ;;
        [Nn])
            exit 1
            ;;
        esac
    done
    

}
function show_help() {
    echo '
Usage: dev_setup.sh [options]
Prepare your environment for running the alice-core services.

Options:
    --clean                 Remove files and folders created by this script
    -h, --help              Show this message
    -fm                     Force mimic build
    -n, --no-error          Do not exit on error (use with caution)
    -p arg, --python arg    Sets the python version to use
    -r, --allow-root        Allow to be run as root (e.g. sudo)
    -sm                     Skip mimic build
'
}

function found_exe() {
    hash "$1" 2>/dev/null
}

# Parse the command line
opt_forcemimicbuild=false
opt_allowroot=false
opt_skipmimicbuild=false
opt_python=python3
disable_precise_later=false
param=''

if found_exe sudo ; then
    SUDO=sudo
elif found_exe doas ; then
    SUDO=doas
elif [[ $opt_allowroot != true ]]; then
    echo 'This script requires "sudo" to install system packages. Please install it, then re-run this script.'
    exit 1
fi

# create and set permissions for logging
if [[ ! -w /var/log/alice/ ]] ; then
    # Creating and setting permissions
    echo 'Creating /var/log/alice/ directory'
    if [[ ! -d /var/log/alice/ ]] ; then
        $SUDO mkdir /var/log/alice/
    fi
    $SUDO chmod 777 /var/log/alice/
fi

for var in "$@" ; do
    # Check if parameter should be read
    if [[ $param == 'python' ]] ; then
        opt_python=$var
        param=""
        continue
    fi

    # Check for options
    if [[ $var == '-h' || $var == '--help' ]] ; then
        show_help
        exit 0
    fi

    if [[ $var == '--clean' ]] ; then
        if clean_alice_files; then
            exit 0
        else
            exit 1
        fi
    fi
    

    if [[ $var == '-r' || $var == '--allow-root' ]] ; then
        opt_allowroot=true
    fi

    if [[ $var == '-fm' ]] ; then
        opt_forcemimicbuild=true
    fi
    if [[ $var == '-n' || $var == '--no-error' ]] ; then
        # Do NOT exit on errors
        set +Ee
    fi
    if [[ $var == '-sm' ]] ; then
        opt_skipmimicbuild=true
    fi
    if [[ $var == '-p' || $var == '--python' ]] ; then
        param='python'
    fi
done

if [[ $(id -u) -eq 0 && $opt_allowroot != true ]] ; then
    echo 'This script should not be run as root or with sudo.' | tee -a /var/log/alice/setup.log
    echo 'If you really need to for this, rerun with --allow-root' | tee -a /var/log/alice/setup.log
    exit 1
fi

function get_YN() {
    # Loop until the user hits the Y or the N key
    echo -e -n "Choice [${CYAN}Y${RESET}/${CYAN}N${RESET}]: "
    while true; do
        read -rN1 -s key
        case $key in
        [Yy])
            return 0
            ;;
        [Nn])
            return 1
            ;;
        esac
    done
}

# If tput is available and can handle multiple colors
if found_exe tput ; then
    if [[ $(tput colors) != "-1" && -z $CI ]]; then
        GREEN=$(tput setaf 2)
        BLUE=$(tput setaf 4)
        CYAN=$(tput setaf 6)
        YELLOW=$(tput setaf 3)
        RESET=$(tput sgr0)
        HIGHLIGHT=$YELLOW
    fi
fi

# Run a setup wizard the very first time that guides the user through some decisions
if [[ ! -f .dev_opts.json && -z $CI ]] ; then
    echo "
$CYAN                    Welcome to ALICE!  $RESET"
    sleep 0.5
    echo '
This script is designed to make working with Alice easy.  During this
first run of dev_setup we will ask you a few questions to help setup
your environment.'
    sleep 0.5
    # The AVX instruction set is an x86 construct
    # ARM has a range of equivalents, unsure which are (un)supported by TF.
    if ! grep -q avx /proc/cpuinfo && ! [[ $(uname -m) == 'arm'* || $(uname -m) == 'aarch64' ]]; then
        echo "
The Precise Wake Word Engine requires the AVX instruction set, which is
not supported on your CPU. Do you want to fall back to the PocketSphinx
engine? Advanced users can build the precise engine with an older
version of TensorFlow (v1.13) if desired and change use_precise to true
in alice.conf.
  Y)es, I want to use the PocketSphinx engine or my own.
  N)o, stop the installation."
        if get_YN ; then
            if [[ ! -f /etc/alice/alice.conf ]]; then
                $SUDO mkdir -p /etc/alice
                $SUDO touch /etc/alice/alice.conf
                $SUDO bash -c 'echo "{ \"use_precise\": false }" > /etc/alice/alice.conf'
            else
                # Ensure dependency installed to merge configs
                disable_precise_later=true
            fi
        else
            echo -e "$HIGHLIGHT N - quit the installation $RESET" | tee -a /var/log/alice/setup.log
            exit 1
        fi
        echo
    fi
    echo "
Do you want to run on 'master' or against a dev branch?  Unless you are
a developer modifying alice-core itself, you should run on the
'master' branch.  It is updated bi-weekly with a stable release.
  Y)es, run on the stable 'master' branch
  N)o, I want to run unstable branches"
    if get_YN ; then
        echo -e "$HIGHLIGHT Y - using 'master' branch $RESET" | tee -a /var/log/alice/setup.log
        branch=master
        git checkout ${branch}
    else
        echo -e "$HIGHLIGHT N - using an unstable branch $RESET" | tee -a /var/log/alice/setup.log
        branch=dev
    fi

    sleep 0.5
    echo "
Alice is actively developed and constantly evolving.  It is recommended
that you update regularly.  Would you like to automatically update
whenever launching Alice?  This is highly recommended, especially for
those running against the 'master' branch.
  Y)es, automatically check for updates
  N)o, I will be responsible for keeping Alice updated."
    if get_YN ; then
        echo -e "$HIGHLIGHT Y - update automatically $RESET" | tee -a /var/log/alice/setup.log
        autoupdate=true
    else
        echo -e "$HIGHLIGHT N - update manually using 'git pull' $RESET" | tee -a /var/log/alice/setup.log
        autoupdate=false
    fi

    #  Pull down mimic source?  Most will be happy with just the package
    if [[ $opt_forcemimicbuild == false && $opt_skipmimicbuild == false ]] ; then
        sleep 0.5
        echo '
Alice uses its Mimic technology to speak to you.  Mimic can run both
locally and from a server.  The local Mimic is more robotic, but always
available regardless of network connectivity.  It will act as a fallback
if unable to contact the Mimic server.

However, building the local Mimic is time consuming -- it can take hours
on slower machines.  This can be skipped, but Alice will be unable to
talk if you lose network connectivity.  Would you like to build Mimic
locally?'
        if get_YN ; then
            echo -e "$HIGHLIGHT Y - Mimic will be built $RESET" | tee -a /var/log/alice/setup.log
        else
            echo -e "$HIGHLIGHT N - skip Mimic build $RESET" | tee -a /var/log/alice/setup.log
            opt_skipmimicbuild=true
        fi
    fi

    echo
    # Add alice-core/bin to the .bashrc PATH?
    sleep 0.5
    echo '
There are several Alice helper commands in the bin folder.  These
can be added to your system PATH, making it simpler to use Alice.
Would you like this to be added to your PATH in the .profile?'
    if get_YN ; then
        echo -e "$HIGHLIGHT Y - Adding Alice commands to your PATH $RESET" | tee -a /var/log/alice/setup.log

        if [[ ! -f ~/.profile_alice ]] ; then
            # Only add the following to the .profile if .profile_alice
            # doesn't exist, indicating this script has not been run before
            {
                echo ''
                echo '# include Alice commands'
                echo 'source ~/.profile_alice'
            } >> ~/.profile
        fi

        echo "
# WARNING: This file may be replaced in future, do not customize.
# set path so it includes Alice utilities
if [ -d \"${TOP}/bin\" ] ; then
    PATH=\"\$PATH:${TOP}/bin\"
fi" > ~/.profile_alice
        echo -e "Type ${CYAN}alice-help$RESET to see available commands."
    else
        echo -e "$HIGHLIGHT N - PATH left unchanged $RESET" | tee -a /var/log/alice/setup.log
    fi

    # Create a link to the 'skills' folder.
    sleep 0.5
    echo
    echo 'The standard location for Alice skills is under /opt/alice/skills.'
    if [[ ! -d /opt/alice/skills ]] ; then
        echo 'This script will create that folder for you.  This requires sudo'
        echo 'permission and might ask you for a password...'
        setup_user=$USER
        setup_group=$(id -gn "$USER")
        $SUDO mkdir -p /opt/alice/skills
        $SUDO chown -R "${setup_user}":"${setup_group}" /opt/alice
        echo 'Created!'
    fi
    if [[ ! -d skills ]] ; then
        ln -s /opt/alice/skills skills
        echo "For convenience, a soft link has been created called 'skills' which leads"
        echo 'to /opt/alice/skills.'
    fi

    # Add PEP8 pre-commit hook
    sleep 0.5
    echo '
(Developer) Do you want to automatically check code-style when submitting code.
If unsure answer yes.
'
    if get_YN ; then
        echo 'Will install PEP8 pre-commit hook...' | tee -a /var/log/alice/setup.log
        INSTALL_PRECOMMIT_HOOK=true
    fi

    # Save options
    echo '{"use_branch": "'$branch'", "auto_update": '$autoupdate'}' > .dev_opts.json

    echo -e '\nInteractive portion complete, now installing dependencies...\n' | tee -a /var/log/alice/setup.log
    sleep 5
fi

function os_is() {
    [[ $(grep "^ID=" /etc/os-release | awk -F'=' '/^ID/ {print $2}' | sed 's/\"//g') == "$1" ]]
}

function os_is_like() {
    grep "^ID_LIKE=" /etc/os-release | awk -F'=' '/^ID_LIKE/ {print $2}' | sed 's/\"//g' | grep -q "\\b$1\\b"
}

function redhat_common_install() {
    $SUDO yum install -y cmake gcc-c++ git python3-devel libtool libffi-devel openssl-devel autoconf automake bison swig portaudio-devel mpg123 flac curl libicu-devel libjpeg-devel fann-devel pulseaudio
    git clone https://github.com/libfann/fann.git
    cd fann
    git checkout b211dc3db3a6a2540a34fbe8995bf2df63fc9939
    cmake .
    $SUDO make install
    cd "$TOP"
    rm -rf fann

}

function debian_install() {
    APT_PACKAGE_LIST=(git python3 python3-dev python3-setuptools libtool \
        libffi-dev libssl-dev autoconf automake bison swig libglib2.0-dev \
        portaudio19-dev mpg123 screen flac curl libicu-dev pkg-config \
        libjpeg-dev libfann-dev build-essential jq pulseaudio \
        pulseaudio-utils)

    if dpkg -V libjack-jackd2-0 > /dev/null 2>&1 && [[ -z ${CI} ]] ; then
        echo "
We have detected that your computer has the libjack-jackd2-0 package installed.
Alice requires a conflicting package, and will likely uninstall this package.
On some systems, this can cause other programs to be marked for removal.
Please review the following package changes carefully."
        read -rp "Press enter to continue"
        $SUDO apt-get install "${APT_PACKAGE_LIST[@]}"
    else
        $SUDO apt-get install -y "${APT_PACKAGE_LIST[@]}"
    fi
}


function open_suse_install() {
    $SUDO zypper install -y git python3 python3-devel libtool libffi-devel libopenssl-devel autoconf automake bison swig portaudio-devel mpg123 flac curl libicu-devel pkg-config libjpeg-devel libfann-devel python3-curses pulseaudio
    $SUDO zypper install -y -t pattern devel_C_C++
}


function fedora_install() {
    $SUDO dnf install -y git python3 python3-devel python3-pip python3-setuptools python3-virtualenv pygobject3-devel libtool libffi-devel openssl-devel autoconf bison swig glib2-devel portaudio-devel mpg123 mpg123-plugins-pulseaudio screen curl pkgconfig libicu-devel automake libjpeg-turbo-devel fann-devel gcc-c++ redhat-rpm-config jq make pulseaudio-utils
}


function arch_install() {
    pkgs=( git python python-pip python-setuptools python-virtualenv python-gobject libffi swig portaudio mpg123 screen flac curl icu libjpeg-turbo base-devel jq )

    if ! pacman -Qs pipewire-pulse > /dev/null
    then
        pulse_pkgs=( pulseaudio pulseaudio-alsa )
        pkgs=( "${pkgs[@]}" "${pulse_pkgs[@]}" )
    fi

    $SUDO pacman -S --needed --noconfirm "${pkgs[@]}"

    pacman -Qs '^fann$' &> /dev/null || (
        git clone  https://aur.archlinux.org/fann.git
        cd fann
        makepkg -srciA --noconfirm
        cd ..
        rm -rf fann
    )
}


function centos_install() {
    $SUDO yum install epel-release
    redhat_common_install
}

function redhat_install() {
    $SUDO yum install -y wget
    wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    $SUDO yum install -y epel-release-latest-7.noarch.rpm
    rm epel-release-latest-7.noarch.rpm
    redhat_common_install

}

function gentoo_install() {
    $SUDO emerge --noreplace dev-vcs/git dev-lang/python dev-python/setuptools dev-python/pygobject dev-python/requests sys-devel/libtool dev-libs/libffi virtual/jpeg dev-libs/openssl sys-devel/autoconf sys-devel/bison dev-lang/swig dev-libs/glib media-libs/portaudio media-sound/mpg123 media-libs/flac net-misc/curl sci-mathematics/fann sys-devel/gcc app-misc/jq media-libs/alsa-lib dev-libs/icu
}

function alpine_install() {
    $SUDO apk add --virtual .makedeps-alice-core \
		alpine-sdk \
		alsa-lib-dev \
		autoconf \
		automake \
		fann-dev \
		git \
		libjpeg-turbo-dev \
		libtool \
		mpg123 \
		pcre2-dev \
		portaudio-dev \
		pulseaudio-utils \
		py3-pip \
		py3-setuptools \
		py3-virtualenv \
		python3 \
		python3-dev \
		swig \
		vorbis-tools
}

function install_deps() {
    echo 'Installing packages...'
    if found_exe zypper ; then
        # OpenSUSE
        echo "$GREEN Installing packages for OpenSUSE...$RESET" | tee -a /var/log/alice/setup.log
        open_suse_install
    elif found_exe yum && os_is centos ; then
        # CentOS
        echo "$GREEN Installing packages for Centos...$RESET" | tee -a /var/log/alice/setup.log
        centos_install
    elif found_exe yum && os_is rhel ; then
        # Redhat Enterprise Linux
        echo "$GREEN Installing packages for Red Hat...$RESET" | tee -a /var/log/alice/setup.log
        redhat_install
    elif os_is_like debian || os_is debian || os_is_like ubuntu || os_is ubuntu || os_is linuxmint; then
        # Debian / Ubuntu / Mint
        echo "$GREEN Installing packages for Debian/Ubuntu/Mint...$RESET" | tee -a /var/log/alice/setup.log
        debian_install
    elif os_is_like fedora || os_is fedora; then
        # Fedora
        echo "$GREEN Installing packages for Fedora...$RESET" | tee -a /var/log/alice/setup.log
        fedora_install
    elif found_exe pacman && (os_is arch || os_is_like arch); then
        # Arch Linux
        echo "$GREEN Installing packages for Arch...$RESET" | tee -a /var/log/alice/setup.log
        arch_install
    elif found_exe emerge && os_is gentoo; then
        # Gentoo Linux
        echo "$GREEN Installing packages for Gentoo Linux ...$RESET" | tee -a /var/log/alice/setup.log
        gentoo_install
    elif found_exe apk && os_is alpine; then
        # Alpine Linux
        echo "$GREEN Installing packages for Alpine Linux...$RESET" | tee -a /var/log/alice/setup.log
        alpine_install
    else
        echo
        echo -e "${YELLOW}Could not find package manager
${YELLOW}Make sure to manually install:$BLUE git python3 python-setuptools python-venv pygobject libtool libffi libjpg openssl autoconf bison swig glib2.0 portaudio19 mpg123 flac curl fann g++ jq\n$RESET" | tee -a /var/log/alice/setup.log

        echo 'Warning: Failed to install all dependencies. Continue? y/N' | tee -a /var/log/alice/setup.log
        read -rn1 continue
        if [[ $continue != 'y' ]] ; then
            exit 1
        fi

    fi
}

VIRTUALENV_ROOT=${VIRTUALENV_ROOT:-"${TOP}/.venv"}

function install_venv() {
    $opt_python -m venv "${VIRTUALENV_ROOT}/" --without-pip

    # Check if old script for python 3.6 is needed
    if "${VIRTUALENV_ROOT}/bin/${opt_python}" --version | grep " 3.6" > /dev/null; then
        GET_PIP_URL="https://bootstrap.pypa.io/pip/3.6/get-pip.py"
    else
        GET_PIP_URL="https://bootstrap.pypa.io/get-pip.py"
    fi

    # Force version of pip for reproducability, but there is nothing special
    # about this version.  Update whenever a new version is released and
    # verified functional.
    curl "${GET_PIP_URL}" | "${VIRTUALENV_ROOT}/bin/${opt_python}" - 'pip==22.3.1'
    # Function status depending on if pip exists
    [[ -x ${VIRTUALENV_ROOT}/bin/pip ]]
}

install_deps

# It's later. Update existing config with jq.
if [[ $disable_precise_later == true ]]; then
    $SUDO bash -c 'jq ". + { \"use_precise\": false }" /etc/alice/alice.conf > tmp.alice.conf' 
                    $SUDO mv -f tmp.alice.conf /etc/alice/alice.conf
fi

# Configure to use the standard commit template for
# this repo only.
git config commit.template .gitmessage

# Check whether to build mimic (it takes a really long time!)
build_mimic='n'
if [[ $opt_forcemimicbuild == true ]] ; then
    build_mimic='y'
else
    # first, look for a build of mimic in the folder
    has_mimic=''
    if [[ -f ${TOP}/mimic/bin/mimic ]] ; then
        has_mimic=$("${TOP}"/mimic/bin/mimic -lv | grep Voice) || true
    fi

    # in not, check the system path
    if [[ -z $has_mimic ]] ; then
        if [[ -x $(command -v mimic) ]] ; then
            has_mimic=$(mimic -lv | grep Voice) || true
        fi
    fi

    if [[ -z $has_mimic ]]; then
        if [[ $opt_skipmimicbuild == true ]] ; then
            build_mimic='n'
        else
            build_mimic='y'
        fi
    fi
fi

if [[ ! -x ${VIRTUALENV_ROOT}/bin/activate ]] ; then
    if ! install_venv ; then
        echo 'Failed to set up virtualenv for alice, exiting setup.' | tee -a /var/log/alice/setup.log
        exit 1
    fi
fi

# Start the virtual environment
# shellcheck source=/dev/null
source "${VIRTUALENV_ROOT}/bin/activate"
cd "$TOP"

# Install pep8 pre-commit hook
HOOK_FILE='./.git/hooks/pre-commit'
if [[ -n $INSTALL_PRECOMMIT_HOOK ]] || grep -q 'ALICE DEV SETUP' $HOOK_FILE; then
    if [[ ! -f $HOOK_FILE ]] || grep -q 'ALICE DEV SETUP' $HOOK_FILE; then
        echo 'Installing PEP8 check as precommit-hook' | tee -a /var/log/alice/setup.log
        echo "#! $(command -v python)" > $HOOK_FILE
        echo '# ALICE DEV SETUP' >> $HOOK_FILE
        cat ./scripts/pre-commit >> $HOOK_FILE
        chmod +x $HOOK_FILE
    fi
fi

PYTHON=$(python -c "import sys;print('python{}.{}'.format(sys.version_info[0], sys.version_info[1]))")

# Add alice-core to the virtualenv path
# (This is equivalent to typing 'add2virtualenv $TOP', except
# you can't invoke that shell function from inside a script)
VENV_PATH_FILE="${VIRTUALENV_ROOT}/lib/$PYTHON/site-packages/_virtualenv_path_extensions.pth"
if [[ ! -f $VENV_PATH_FILE ]] ; then
    echo 'import sys; sys.__plen = len(sys.path)' > "$VENV_PATH_FILE" || return 1
    echo "import sys; new=sys.path[sys.__plen:]; del sys.path[sys.__plen:]; p=getattr(sys,'__egginsert',0); sys.path[p:p]=new; sys.__egginsert = p+len(new)" >> "$VENV_PATH_FILE" || return 1
fi

if ! grep -q "$TOP" "$VENV_PATH_FILE" ; then
    echo 'Adding alice-core to virtualenv path' | tee -a /var/log/alice/setup.log
    sed -i.tmp "1 a$TOP" "$VENV_PATH_FILE"
fi

# install required python modules
if ! pip install -r requirements/requirements.txt ; then
    echo 'Warning: Failed to install required dependencies. Continue? y/N' | tee -a /var/log/alice/setup.log
    read -rn1 continue
    if [[ $continue != 'y' ]] ; then
        exit 1
    fi
fi

# install optional python modules
if [[ ! $(pip install -r requirements/extra-audiobackend.txt) ||
    ! $(pip install -r requirements/extra-stt.txt) ||
    ! $(pip install -r requirements/extra-mark1.txt) ]] ; then
    echo 'Warning: Failed to install some optional dependencies. Continue? y/N' | tee -a /var/log/alice/setup.log
    read -rn1 continue
    if [[ $continue != 'y' ]] ; then
        exit 1
    fi
fi


if ! pip install -r requirements/tests.txt ; then
    echo "Warning: Test requirements failed to install. Note: normal operation should still work fine..." | tee -a /var/log/alice/setup.log
fi

SYSMEM=$(free | awk '/^Mem:/ { print $2 }')
MAXCORES=$((SYSMEM / 2202010))
MINCORES=1
CORES=$(nproc)

# ensure MAXCORES is > 0
if [[ $MAXCORES -lt 1 ]] ; then
    MAXCORES=${MINCORES}
fi

# Be positive!
if ! [[ $CORES =~ ^[0-9]+$ ]] ; then
    CORES=$MINCORES
elif [[ $MAXCORES -lt $CORES ]] ; then
    CORES=$MAXCORES
fi

echo "Building with $CORES cores." | tee -a /var/log/alice/setup.log

#build and install pocketsphinx
#build and install mimic

cd "$TOP"

if [[ $build_mimic == 'y' || $build_mimic == 'Y' ]] ; then
    echo 'WARNING: The following can take a long time to run!' | tee -a /var/log/alice/setup.log
    "${TOP}/scripts/install-mimic.sh" "$CORES"
else
    echo 'Skipping mimic build.' | tee -a /var/log/alice/setup.log
fi

# set permissions for common scripts
chmod +x start-alice.sh
chmod +x stop-alice.sh
chmod +x bin/alice-cli-client
chmod +x bin/alice-help
chmod +x bin/alice-mic-test
chmod +x bin/alice-msk
chmod +x bin/alice-msm
chmod +x bin/alice-pip
chmod +x bin/alice-say-to
chmod +x bin/alice-skill-testrunner
chmod +x bin/alice-speak

#Store a fingerprint of setup
md5sum requirements/requirements.txt requirements/extra-audiobackend.txt requirements/extra-stt.txt requirements/extra-mark1.txt requirements/tests.txt dev_setup.sh > .installed

echo 'Alice setup complete! Logs can be found at /var/log/alice/setup.log' | tee -a /var/log/alice/setup.log