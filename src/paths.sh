if ! (( ${HALCYON_INTERNAL_PATHS:-0} )); then
	export HALCYON_INTERNAL_PATHS=1

	is_debian=0
	is_redhat=0
	case "${HALCYON_INTERNAL_PLATFORM}" in
	'linux-debian-'*|'linux-ubuntu-'*)
		is_debian=1;;
	'linux-centos-'*|'linux-fedora-'*)
		is_redhat=1;;
	esac

	export HALCYON_BASE="${HALCYON_BASE:-/app}"

	path=()
	path+=( "${HALCYON_DIR}" )
	path+=( "${HALCYON_BASE}/bin" )
	path+=( "${HALCYON_BASE}/usr/bin" )
	path+=( "${HALCYON_BASE}/ghc/bin" )
	path+=( "${HALCYON_BASE}/cabal/bin" )
	path+=( "${HALCYON_BASE}/sandbox/bin" )
	path+=( "${HALCYON_BASE}/sandbox/usr/bin" )
	export PATH=$( IFS=':' && echo "${path[*]}:${PATH:-}" )

	path=()
	path+=( "${HALCYON_BASE}/include" )
	path+=( "${HALCYON_BASE}/usr/include" )
	path+=( "${HALCYON_BASE}/sandbox/include" )
	path+=( "${HALCYON_BASE}/sandbox/usr/include" )
	if (( is_debian )); then
		path+=( "${HALCYON_BASE}/include/x86_64-linux-gnu" )
		path+=( "${HALCYON_BASE}/usr/include/x86_64-linux-gnu" )
		path+=( "${HALCYON_BASE}/sandbox/include/x86_64-linux-gnu" )
		path+=( "${HALCYON_BASE}/sandbox/usr/include/x86_64-linux-gnu" )
	fi
	export CPATH=$( IFS=':' && echo "${path[*]}:${CPATH:-}" )

	path=()
	path+=( "${HALCYON_BASE}/lib" )
	path+=( "${HALCYON_BASE}/usr/lib" )
	path+=( "${HALCYON_BASE}/ghc/usr/lib" )
	path+=( "${HALCYON_BASE}/sandbox/lib" )
	path+=( "${HALCYON_BASE}/sandbox/usr/lib" )
	if (( is_debian )); then
		path+=( "${HALCYON_BASE}/lib/x86_64-linux-gnu" )
		path+=( "${HALCYON_BASE}/usr/lib/x86_64-linux-gnu" )
		path+=( "${HALCYON_BASE}/sandbox/lib/x86_64-linux-gnu" )
		path+=( "${HALCYON_BASE}/sandbox/usr/lib/x86_64-linux-gnu" )
	elif (( is_redhat )); then
		path+=( "${HALCYON_BASE}/lib64" )
		path+=( "${HALCYON_BASE}/usr/lib64" )
		path+=( "${HALCYON_BASE}/sandbox/lib64" )
		path+=( "${HALCYON_BASE}/sandbox/usr/lib64" )
	fi
	export LIBRARY_PATH=$( IFS=':' && echo "${path[*]}:${LIBRARY_PATH:-}" )
	export LD_LIBRARY_PATH=$( IFS=':' && echo "${path[*]}:${LD_LIBRARY_PATH:-}" )

	path=()
	path+=( "${HALCYON_BASE}/usr/lib/pkgconfig" )
	path+=( "${HALCYON_BASE}/usr/share/pkgconfig" )
	path+=( "${HALCYON_BASE}/sandbox/usr/lib/pkgconfig" )
	path+=( "${HALCYON_BASE}/sandbox/usr/share/pkgconfig" )
	if (( is_debian )); then
		path+=( "${HALCYON_BASE}/usr/lib/x86_64-linux-gnu/pkgconfig" )
		path+=( "${HALCYON_BASE}/sandbox/usr/lib/x86_64-linux-gnu/pkgconfig" )
	fi
	export PKG_CONFIG_PATH=$( IFS=':' && echo "${path[*]}:${PKG_CONFIG_PATH:-}" )

	export PKG_CONFIG_SYSROOT_DIR="${HALCYON_BASE}/sandbox"

	# NOTE: A UTF-8 locale is needed to work around a Cabal issue.
	# https://github.com/haskell/cabal/issues/1883

	export LANG="${LANG:-C.UTF-8}"
fi
