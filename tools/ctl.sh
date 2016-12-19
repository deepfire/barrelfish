#!/bin/sh

warn() {
    echo ";  WARNING: $*" >&2
}
errormsg() {
    echo ";  ERROR: $*" >&2
}
fail() {
    errormsg "$*"
    exit 1
}

alias arg='test $# -ge 1 || usage "missing value for"'
alias argnz='test $# -ge 1 || usage "empty value for"'
alias argnzd='test $# -ge 1 -a -d "$1" || usage "missing directory for"'
alias argnzf='test $# -ge 1 -a -f "$1" || usage "missing file for"'

###
### Argument defaults
###
arg_arch=x86_64
arg_cc=gcc
arg_irony=
arg_cores=$(grep vendor_id /proc/cpuinfo | wc -l)
arg_cls=
arg_dry_run=

usage() {
    test $# -ge 1 && { errormsg "$*"; echo >&2; }
    cat >&2 <<EOF
  Usage:
    $0 OPTIONS* OP [ARGS..]

  Developer helper script.

  Options:

    --arch ARCH         Set architecture.  Defaults to ${arg_arch}
    --buildroot DIR     Set build root.  Defaults to ${arg_buildroot}
    --cc GCC            Use this compiler, when overriding defaults.
                          Defaults to ${arg_cc}
    --cls               Clear terminal scrollback & screen before proceeding
    --irony             As a side-effect to compilation, create the Clang
                          compilation database in ${arg_buildroot}/compile_commands.json
                          using 'bear'
    --cores NCPUS       Set make parallelism.  Defaults to ${arg_cores}
    --dry[-run]         Do not execute side-effects, only print them
    --verbose           Verbose operation

  Context-less operations:

    clean                       Clear the buildroot
    clean-kernel                Clean kernel build artifacts
    dis-kernel [SYM]            Disassemble the kernel, optionally jumping to SYM
    initial-hake                Initial Hake run
    kernel                      Build the kernel for arch=${arg_arch}
    rehake                      Re-run Hake
    sim                         Launch a simulated session under GDB control

EOF
    exit 1
}

###
### Argument processing
###
VERBOSE=${VERBOSE:-}

set -u ## Undefined variable firewall enabled
while test $# -ge 1
do
    case "$1"
    in
	--arch )                arg_arch=$2;      shift;;
	--buildroot )           arg_buildroot=$2; shift;;
	--cc )                  arg_cc=$2;        shift;;
	--irony )               arg_irony='true';;
	--cls )                 echo -ne "\033c";;
	--cores )               arg_cores=$2;     shift;;
	--dry-run | --dry )     arg_dry_run="echo";;
	--verbose )             VERBOSE="--verbose";;
        "--"* ) usage "unknown option: $1";;
        * )     break;;
    esac
    shift
done

arg_buildroot=${arg_buildroot:-./build.${arg_arch}}

###
### Lib
###
run() {
	if test -n "${arg_dry_run}"
	then echo "$@" >&2
	else "$@"
	fi
}

gdb_arch_string () {
	case ${arg_arch} in
		x86_64 ) echo 'i386:x86-64:intel';;
		* )      fail 'unsupported architecture';;
	esac
}

lib_hake_sh_needed () {
	test ! -f ${arg_buildroot}/Makefile ||
	test ! -f ${arg_buildroot}/hake/Config.hs
}

lib_ensure_makefile () {
	if lib_hake_sh_needed
	then op_initial_hake
	fi
}

lib_call_make () {
	if test -n "${arg_irony}"
	then run make -C ${arg_buildroot} -j ${arg_cores} "$@" "CC_${arg_arch}=bear ${arg_cc}"
	else run make -C ${arg_buildroot} -j ${arg_cores} "$@"
	fi
}

###
### Ops
###
op_clean () {
	run rm ./${arg_buildroot} -rf && mkdir ${arg_buildroot}
}
op_clean_kernel () {
	run rm ./${arg_buildroot}/${arg_arch}/kernel -rf
}
op_dis_kernel () {
	run objdump -dx ${arg_buildroot}/${arg_arch}/sbin/cpu | run less ${1:+--pattern="<$1>:$"}
}
op_initial_hake () {
	run mkdir -p ${arg_buildroot} && run cd ${arg_buildroot} && run ../hake/hake.sh -s ../ -a ${arg_arch}
}
op_rehake () {
	run rm -f ${arg_buildroot}/hake/Config.hs
        op_initial_hake
}
op_sim () {
	lib_ensure_makefile
	lib_call_make qemu_${arg_arch}_debug QEMU_EXTRA_ARGS=--display
}

###
### Main & toplevel command dispatch
###
if test $# -ge 1
then argnz "OPERATION"; operation=$1; shift
else warn "operation not provided, exiting"; usage
fi

test -z "${VERBOSE}" -o "${operation}" = "list-ops" || {
    echo "arg_arch=$arg_arch arg_buildroot=$arg_buildroot" >&2
}

test -z "${VERBOSE}" -o "${operation}" = "list-ops" || set -x

case ${operation} in
list-ops )
	echo clean initial-hake rehake sim
	;;

clean )            op_clean;;
clean-kernel )     op_clean_kernel;;
dis-kernel )       op_dis_kernel "$@";;
initial-hake )     op_initial_hake;;
kernel )           lib_ensure_makefile; lib_call_make ${arg_arch}/sbin/cpu;;
rehake )           op_rehake;;
sim )              op_sim;;

###
### WARNING:  make sure 'list-ops' is up-to-date!
###

* )
	usage "unknown operation: ${operation}";;
esac
